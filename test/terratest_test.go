package test

import (
	"context"
	"fmt"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/lambda"
	"github.com/aws/aws-sdk-go-v2/service/ssm"
	"github.com/aws/aws-sdk-go-v2/service/ssm/types"
	"github.com/gruntwork-io/terratest/modules/http-helper"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
)

func TestDynamicStringService(t *testing.T) {
	t.Parallel()

	region := "eu-west-2"
	uniqueID := strings.ToLower(random.UniqueId())
	env := fmt.Sprintf("test-%s", uniqueID)
	projectName := "dynamic-string-service"
	paramName := fmt.Sprintf("/%s/%s/dynamic_string", projectName, env)
	initial := "Hello Terratest"
	updated := "Updated by Terratest"

	useLocal := os.Getenv("LOCALSTACK") == "1"
	lsEndpoint := os.Getenv("LOCALSTACK_ENDPOINT")
	if lsEndpoint == "" {
		lsEndpoint = "http://localhost:4566"
	}

	vars := map[string]interface{}{
		"aws_region":             region,
		"environment":            env,
		"ssm_parameter_name":     paramName,
		"dynamic_string_default": initial,
	}
	if useLocal {
		vars["use_localstack"] = true
		vars["localstack_endpoint"] = lsEndpoint
	}

	terraformOptions := &terraform.Options{
		TerraformDir:   "..",
		Vars:           vars,
		NoColor:        true,
		TerraformBinary: "terraform",
	}

	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)

	var apiURL string
	if !useLocal {
		apiURL = terraform.Output(t, terraformOptions, "api_base_url")
	}
	lambdaName := terraform.Output(t, terraformOptions, "lambda_function_name")

	expectedInitial := fmt.Sprintf("<h1>The saved string is %s</h1>", initial)
	if !useLocal {
		http_helper.HttpGetWithRetry(t, apiURL, nil, 200, expectedInitial, 10, 5*time.Second)
	}

	var cfg aws.Config
	var err error
	if useLocal {
		resolver := aws.EndpointResolverWithOptionsFunc(func(service, region string, options ...interface{}) (aws.Endpoint, error) {
			return aws.Endpoint{URL: lsEndpoint, HostnameImmutable: true}, nil
		})
		cfg, err = config.LoadDefaultConfig(context.Background(),
			config.WithRegion(region),
			config.WithEndpointResolverWithOptions(resolver),
		)
	} else {
		cfg, err = config.LoadDefaultConfig(context.Background(), config.WithRegion(region))
	}
	if err != nil {
		t.Fatalf("failed to load AWS config: %v", err)
	}

	if useLocal {
		// Directly invoke Lambda and check the response body
		l := lambda.NewFromConfig(cfg)
		out, err := l.Invoke(context.Background(), &lambda.InvokeInput{
			FunctionName: &lambdaName,
			Payload:      []byte("{}"),
		})
		if err != nil {
			t.Fatalf("lambda invoke failed: %v", err)
		}
		if !strings.Contains(string(out.Payload), expectedInitial) {
			t.Fatalf("unexpected lambda payload: %s", string(out.Payload))
		}
	}

	smClient := ssm.NewFromConfig(cfg)
	_, err = smClient.PutParameter(context.Background(), &ssm.PutParameterInput{
		Name:      aws.String(paramName),
		Value:     aws.String(updated),
		Type:      types.ParameterTypeString,
		Overwrite: aws.Bool(true),
	})
	if err != nil {
		t.Fatalf("failed to update SSM parameter: %v", err)
	}

	expectedUpdated := fmt.Sprintf("<h1>The saved string is %s</h1>", updated)
	if useLocal {
		l := lambda.NewFromConfig(cfg)
		out, err := l.Invoke(context.Background(), &lambda.InvokeInput{
			FunctionName: &lambdaName,
			Payload:      []byte("{}"),
		})
		if err != nil {
			t.Fatalf("lambda invoke failed: %v", err)
		}
		if !strings.Contains(string(out.Payload), expectedUpdated) {
			t.Fatalf("unexpected lambda payload (updated): %s", string(out.Payload))
		}
	} else {
		http_helper.HttpGetWithRetry(t, apiURL, nil, 200, expectedUpdated, 15, 4*time.Second)
	}
}

func TestDynamicStringUpdateOnly(t *testing.T) {
	t.Parallel()

	region := "eu-west-2"
	uniqueID := strings.ToLower(random.UniqueId())
	env := fmt.Sprintf("test-upd-%s", uniqueID)
	projectName := "dynamic-string-service"
	paramName := fmt.Sprintf("/%s/%s/dynamic_string", projectName, env)
	initial := "Init For Update Test"
	updated := "Updated In Update Test"

	useLocal := os.Getenv("LOCALSTACK") == "1"
	lsEndpoint := os.Getenv("LOCALSTACK_ENDPOINT")
	if lsEndpoint == "" {
		lsEndpoint = "http://localhost:4566"
	}

	vars := map[string]interface{}{
		"aws_region":             region,
		"environment":            env,
		"ssm_parameter_name":     paramName,
		"dynamic_string_default": initial,
	}
	if useLocal {
		vars["use_localstack"] = true
		vars["localstack_endpoint"] = lsEndpoint
	}

	terraformOptions := &terraform.Options{
		TerraformDir:   "..",
		Vars:           vars,
		NoColor:        true,
		TerraformBinary: "terraform",
	}

	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)

	var apiURL string
	if !useLocal {
		apiURL = terraform.Output(t, terraformOptions, "api_base_url")
	}
	lambdaName := terraform.Output(t, terraformOptions, "lambda_function_name")

	expectedInitial := fmt.Sprintf("<h1>The saved string is %s</h1>", initial)

	var cfg aws.Config
	var err error
	if useLocal {
		resolver := aws.EndpointResolverWithOptionsFunc(func(service, region string, options ...interface{}) (aws.Endpoint, error) {
			return aws.Endpoint{URL: lsEndpoint, HostnameImmutable: true}, nil
		})
		cfg, err = config.LoadDefaultConfig(context.Background(),
			config.WithRegion(region),
			config.WithEndpointResolverWithOptions(resolver),
		)
	} else {
		cfg, err = config.LoadDefaultConfig(context.Background(), config.WithRegion(region))
	}
	if err != nil {
		t.Fatalf("failed to load AWS config: %v", err)
	}

	// Verify initial value
	if useLocal {
		l := lambda.NewFromConfig(cfg)
		out, err := l.Invoke(context.Background(), &lambda.InvokeInput{
			FunctionName: &lambdaName,
			Payload:      []byte("{}"),
		})
		if err != nil {
			t.Fatalf("lambda invoke failed: %v", err)
		}
		if !strings.Contains(string(out.Payload), expectedInitial) {
			t.Fatalf("unexpected initial payload: %s", string(out.Payload))
		}
	} else {
		http_helper.HttpGetWithRetry(t, apiURL, nil, 200, expectedInitial, 10, 5*time.Second)
	}

	// Update parameter
	smClient := ssm.NewFromConfig(cfg)
	_, err = smClient.PutParameter(context.Background(), &ssm.PutParameterInput{
		Name:      aws.String(paramName),
		Value:     aws.String(updated),
		Type:      types.ParameterTypeString,
		Overwrite: aws.Bool(true),
	})
	if err != nil {
		t.Fatalf("failed to update SSM parameter: %v", err)
	}

	// Verify updated value
	expectedUpdated := fmt.Sprintf("<h1>The saved string is %s</h1>", updated)
	if useLocal {
		l := lambda.NewFromConfig(cfg)
		out, err := l.Invoke(context.Background(), &lambda.InvokeInput{
			FunctionName: &lambdaName,
			Payload:      []byte("{}"),
		})
		if err != nil {
			t.Fatalf("lambda invoke failed: %v", err)
		}
		if !strings.Contains(string(out.Payload), expectedUpdated) {
			t.Fatalf("unexpected updated payload: %s", string(out.Payload))
		}
	} else {
		http_helper.HttpGetWithRetry(t, apiURL, nil, 200, expectedUpdated, 15, 4*time.Second)
	}
}
