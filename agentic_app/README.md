# Agentic Application Sample Configuration

This sample configuration demonstrates building a simple agentic application using MDAA, featuring a custom agent runtime powered by Amazon Bedrock AgentCore. This provides a starting point for customers to build intelligent, autonomous applications that can reason, plan, and execute tasks.

***

## Architecture Overview

This configuration deploys a complete agentic application with:

1. **Custom Agent Runtime**: Containerized agent using the Strands framework for flexible agent logic
2. **Secure Authentication**: JWT-based access control via Amazon Cognito
3. **Network Security**: VPC-secured deployment with private subnets
4. **Scalable Infrastructure**: Managed runtime with automatic scaling and high availability
5. **Observability**: CloudWatch logging, metrics, and X-Ray tracing
6. **Operational Alerting**: CloudWatch alarms on error rate and throttling, plus EventBridge rules on security-relevant AgentCore events, notifying a CMK-encrypted SNS topic
7. **API Access**: Runtime endpoint for programmatic agent invocation
8. **IAM Security**: Least-privilege roles with appropriate permissions

***

## Deployment Instructions

### Step-by-Step Deployment

1. Edit the `mdaa.yaml` to specify an organization name. This must be a globally unique name, as it is used in the naming of all deployed resources.

2. Configure Context Values - Update the `mdaa.yaml` file under the `context:` section with your environment-specific values:
   - `cognito_user_pool_id`: Your Cognito User Pool ID (e.g., `us-east-1_ABC123`)
   - `cognito_client_id`: Your Cognito App Client ID
   - `vpc_id`: VPC ID containing the subnets below
   - `security_group_id`: Security group ID for the runtime (must allow outbound traffic)
   - `subnet_id_1`: First private subnet ID
   - `subnet_id_2`: Second private subnet ID (for high availability)
   - `notification_email`: Address subscribed to the alarm/alert SNS topic. SNS sends a confirmation request that must be accepted before any notification is delivered, so use a mailbox you can read.

3. Ensure you are authenticated to your target AWS account and have CDK bootstrapped in your target region.

4. Deploy the architecture:
   ```bash
   npx @aws-mdaa/cli deploy
   ```

***

## Configuration Files

### Directory Structure
```
agentic_app/
├── mdaa.yaml                                           # Main orchestration config
├── tags.yaml                                           # Resource tagging
└── bedrock-agentcore-runtime/
    ├── bedrock-agentcore-runtime.yaml                 # Runtime configuration
    └── agent_core_code/
        ├── agent.py                                    # FastAPI agent server
        ├── Dockerfile                                  # Container image definition
        ├── pyproject.toml                              # Python dependencies
        ├── uv.lock                                     # Dependency lock file
        └── .python-version                             # Python version specification
```

### Key Configuration Files

#### mdaa.yaml - Main Configuration
**⚠️ Required Changes Before Deployment:**
- `organization`: Must be globally unique (used in resource naming)
- `cognito_user_pool_id`: Your Cognito User Pool ID
- `cognito_client_id`: Your Cognito App Client ID
- `vpc_id`: VPC containing the subnets below
- `security_group_id`: Security group for the runtime
- `subnet_id_1`, `subnet_id_2`: Private subnet IDs
- `notification_email`: Address to subscribe to the alarm/alert SNS topic

```yaml
region: default
organization: <org>  # CHANGE THIS

context:
  cognito_user_pool_id: <>      # CHANGE THIS
  cognito_client_id: <>         # CHANGE THIS
  vpc_id: <>                    # CHANGE THIS
  security_group_id: <>         # CHANGE THIS
  subnet_id_1: <>               # CHANGE THIS
  subnet_id_2: <>               # CHANGE THIS
  notification_email: <>        # CHANGE THIS

domains:
  ai:
    environments:
      dev:
        modules:
          agent-core-hello:
            module_path: "@aws-mdaa/bedrock-agentcore-runtime"
            module_configs:
              - ./bedrock-agentcore-runtime/bedrock-agentcore-runtime.yaml
```

#### Key Module Configurations

- **bedrock-agentcore-runtime.yaml**: Configures the AgentCore runtime with container settings, network configuration, JWT authentication, and runtime endpoint
- **tags.yaml**: Standard tags applied to all resources
- **agent_core_code/agent.py**: FastAPI server implementing the Strands agent with `/invocations` and `/ping` endpoints
- **agent_core_code/Dockerfile**: Container image definition for ARM64 platform

***

## Components

### Agent Runtime Infrastructure

The runtime infrastructure provides:
- **Containerized Deployment**: Custom Docker container with FastAPI agent server
- **Image Management**: ECR repository for secure container image storage
- **Network Security**: VPC-secured deployment with private subnets
- **Access Control**: JWT authorizer for secure API access
- **API Endpoint**: Runtime endpoint for programmatic agent invocation
- **IAM Security**: Execution role with least-privilege permissions

### Agent Implementation

The Strands-based agent implementation includes:
- **API Server**: FastAPI server with `/invocations` endpoint for agent processing
- **Health Monitoring**: `/ping` endpoint for health checks
- **Data Validation**: Pydantic models for request/response validation
- **Error Handling**: Comprehensive error handling and logging
- **Model Integration**: Direct integration with Bedrock foundation models via Strands framework

### Security & Compliance

The deployment implements:
- **Authentication**: JWT-based authentication via Amazon Cognito
- **Authorization**: Fine-grained IAM permissions for runtime execution
- **Encryption**: Data encryption in transit and at rest
- **Network Isolation**: VPC deployment with private subnets
- **Audit Logging**: CloudWatch logs for all agent interactions

***

## Use Cases

This agentic application starter is ideal for:
- **Intelligent Assistants**: Build conversational agents that can reason and take actions
- **Task Automation**: Create agents that autonomously execute complex workflows
- **Decision Support**: Deploy agents that analyze data and provide recommendations
- **Customer Service**: Implement intelligent customer support agents with custom business logic
- **Process Orchestration**: Build agents that coordinate multiple systems and services
- **Research & Development**: Prototype and test new agentic capabilities and patterns

***

## Usage Instructions

Once the MDAA deployment is complete, follow these steps to test and interact with your agentic application.

### 1. Retrieve Runtime Information

The deployment stores runtime details in SSM Parameter Store:

```bash
# You need to update these variables based on your mdaa.yaml
ORG=<your-org>                 # change this!
REGION=<your-region>           # change this! 
MODULE_NAME="agent-core-app"   # default value from the sample config
DOMAIN="ai"                    # default value from the sample config
RUNTIME_PATH="/${ORG}/${DOMAIN}/${MODULE_NAME}/agentruntime"
echo $RUNTIME_PATH

# List all agentcore runtime ARNs
RUNTIME_ARN=$(aws ssm get-parameters-by-path \
  --path ${RUNTIME_PATH} \
  --recursive \
  --region ${REGION} \
  --query "Parameters[?ends_with(Name, '/arn')].Value | [0]" \
  --output text)

echo "Runtime ARN: ${RUNTIME_ARN}"
```

### 2. Create Cognito User (if it's not created)

To get a valid JWT token from your Cognito User Pool, you need to create test user:

```bash

USER_POOL_ID=<your-user-pool-id>     # change this! 
COGNITO_CLIENT_ID=<your-client-id>   # change this! 

# Create user 
USERNAME="testuser"
PASSWORD="TempPass1@"

aws cognito-idp admin-create-user \
 --user-pool-id ${USER_POOL_ID} \
 --username ${USERNAME} \
 --temporary-password ${PASSWORD} \
 --message-action SUPPRESS \
 --region ${REGION}

aws cognito-idp admin-set-user-password \
 --user-pool-id ${USER_POOL_ID} \
 --username ${USERNAME} \
 --password ${PASSWORD} \
 --permanent \
 --region ${REGION}
```

### 3. Obtain the Bearer Token from Cognito

To invoke the runtime, you need a valid Bearer Token from your Cognito User Pool:

```bash
ID_TOKEN=$(aws cognito-idp initiate-auth \
 --client-id ${COGNITO_CLIENT_ID} \
 --auth-flow USER_PASSWORD_AUTH \
 --auth-parameters USERNAME=${USERNAME},PASSWORD=${PASSWORD} \
 --region ${REGION} \
 --query 'AuthenticationResult.IdToken' \
 --output text)
```

### 4. Invoke the Runtime

Since the runtime is configured for OAuth, you must use an HTTPS request with a Bearer token rather than the AWS CLI:


```bash
# URL-encode the runtime ARN
ESCAPED_ARN=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${RUNTIME_ARN}', safe=''))")
echo $ESCAPED_ARN

curl -X POST "https://bedrock-agentcore.${REGION}.amazonaws.com/runtimes/${ESCAPED_ARN}/invocations?qualifier=DEFAULT" \
 -H "Authorization: Bearer ${ID_TOKEN}" \
 -H "Content-Type: application/json" \
 -d '{"prompt": "Hello, what can you help me with?"}'

```

Successful invocation example:
```
"Hello! I'm here to help you with:\n\n1. **Math Calculations** - I can perform a wide range of mathematical operations, including:\n   - Basic arithmetic (addition, subtraction, multiplication, division)\n   - Complex expressions and equations\n   - Solving equations and systems of equations\n   - Calculus operations (derivatives, integrals)\n   - Limits and series expansions\n   - Matrix operations\n   - And much more!\n\n2. **Weather Information** - I can tell you current weather conditions.\n\nFeel free to ask me anything! For example, you could ask:\n- \"Calculate 25 × 3 + 15\"\n- \"Solve x² + 2x - 8 = 0\"\n- \"What's the derivative of sin(x)?\"\n- \"What's the weather?\"\n\nWhat would you like help with?"
```

### 5. Monitor Runtime Performance

- **CloudWatch Logs**: Monitor agent interactions and container logs
- **CloudWatch Metrics**: Track AgentCore service metrics (`Invocations`, `SystemErrors`, `UserErrors`, `Throttles`) in the `AWS/Bedrock-AgentCore` namespace. Note this differs from the `bedrock-agentcore` namespace, which is where the agent's own custom metrics are published.
- **X-Ray Traces**: Analyze request traces for performance optimization

### 6. Confirm the Alerting Subscription

The `alarms` block deploys a CMK-encrypted SNS topic and subscribes `notification_email` to it. **SNS will not deliver anything until that subscription is confirmed** — check the mailbox for the confirmation request and accept it. Until then the alarms deploy and evaluate normally but notify nobody.

Two alarms are created: error rate (`SystemErrors + UserErrors` as a percentage of `Invocations`, over 10%) and throttle count (over 100). Both require 2 of 3 breaching 5-minute periods, which avoids paging on a single error on a low-traffic runtime. Both treat missing data as not breaching, so an idle runtime reports `OK` rather than `INSUFFICIENT_DATA` — note this means a runtime serving zero invocations looks the same as a healthy idle one.

The topic ARN is exported to SSM if you want to attach additional subscribers (a chatbot integration, PagerDuty, an existing distribution list) out of band:

```bash
aws ssm get-parameters-by-path \
  --path "/${ORG}/${DOMAIN}/${MODULE_NAME}/topic" \
  --recursive --region ${REGION} \
  --query "Parameters[?ends_with(Name, '/arn')].Value | [0]" --output text
```

### 7. Enable CloudTrail for the EventBridge Rules

The `eventBridgeAlerts` block creates two rules — `auth-failure` and `config-change` — that match this runtime's AgentCore CloudTrail events and notify the same SNS topic.

**These rules require a CloudTrail trail in this account and region, which this starter kit does not deploy.** Without one they deploy cleanly and never fire, which reads as coverage you do not have. Two categories behave differently:

- **Management events** (`UpdateAgentRuntime`, `DeleteAgentRuntime`) are logged by default on any trail, so `config-change` works as soon as a trail exists.
- **Data events** (`InvokeAgentRuntime`, and the authorization failures that accompany it) are **off by default** and require an explicit advanced event selector for resource types `AWS::BedrockAgentCore::Runtime` and `AWS::BedrockAgentCore::RuntimeEndpoint`. `auth-failure` stays silent until that is enabled.

Deploy a trail using the MDAA audit-trail module or create one out of band, then verify matches in the EventBridge console before relying on these alerts. To remove the rules instead, delete the `eventBridgeAlerts` block from the runtime config.

***

## Agent Customization

### Modifying the Agent Code

The agent implementation is in `bedrock-agentcore-runtime/agent_core_code/agent.py`. You can customize:

1. **Agent Logic**: Modify the Strands agent initialization and processing
2. **Input/Output Format**: Update Pydantic models for different request/response structures
3. **Additional Endpoints**: Add new FastAPI endpoints for specialized functionality
4. **Error Handling**: Enhance error handling and validation logic

### Updating Dependencies

Dependencies are managed via `pyproject.toml`:

```bash
cd bedrock-agentcore-runtime/agent_core_code

# Add new dependencies
uv add <package-name>

# Update lock file
uv lock
```

### Rebuilding the Container

After code changes, redeploy to rebuild and push the container:

```bash
npx @aws-mdaa/cli deploy
```

***

## Extending the Application

This sample provides a foundation for building more sophisticated agentic applications:

### Adding Knowledge Bases
Integrate Bedrock Knowledge Bases for RAG (Retrieval Augmented Generation) capabilities to give your agent access to domain-specific knowledge.

### Multi-Agent Systems
Deploy multiple agent runtimes with different specializations and orchestrate them to handle complex tasks.

### Tool Integration
Extend the agent with custom tools and APIs to interact with external systems, databases, and services.

### Workflow Orchestration
Implement Step Functions or other orchestration services to coordinate multi-step agent workflows.

### Advanced Authentication
Integrate with enterprise identity providers (SAML, OIDC) for single sign-on and fine-grained access control.

***

## Troubleshooting

### Common Issues

1. **Unrecognized resource types error during deployment**:
   ```
   ValidationError: Template format error: Unrecognized resource types: 
   [AWS::BedrockAgentCore::Runtime, AWS::BedrockAgentCore::RuntimeEndpoint]
   ```
   
   **Cause**: The region you're deploying to doesn't support Bedrock AgentCore yet.
   
   **Solution**: 
   - Check the [Bedrock AgentCore supported regions documentation](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/agentcore-regions.html) for the list of regions that support AgentCore
   - Update the `region` field in your `mdaa.yaml` to a supported region
   - Ensure your VPC, subnets, and security groups are in the same supported region

2. **JWT authentication failures**:
   - Verify the Cognito User Pool ID and Client ID are correct in the configuration
   - Ensure the discovery URL is properly formatted and ends with `/.well-known/openid-configuration`
   - Check that the JWT token's `aud` claim matches the configured `allowedAudience`
   - Verify the token hasn't expired

3. **Container build or deployment failures**:
   - Check that Docker is installed and running on your deployment machine
   - Verify ECR permissions for pushing images
   - Ensure the specified platform (`linux/arm64` or `linux/amd64`) is supported
   - Review CloudWatch logs for container startup errors

4. **Network connectivity issues**:
   - Verify security groups allow outbound traffic to AWS services
   - Ensure subnets have routes to NAT Gateway or VPC endpoints for AWS service access
   - Check that the runtime can reach Bedrock endpoints
   - Verify VPC DNS resolution is enabled

5. **Runtime invocation failures**:
   - Confirm the runtime is in "Active" state in the Bedrock console
   - Verify the runtime endpoint is properly configured
   - Check IAM permissions for the runtime execution role
   - Review CloudWatch logs for detailed error messages

6. **AgentCore runtime-specific issues after successful deployment**:
   - For detailed troubleshooting of runtime behavior, performance, or operational issues, refer to the [Bedrock AgentCore Runtime Troubleshooting Guide](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-troubleshooting.html)
   - This includes guidance on container startup issues, memory/CPU constraints, timeout configurations, and runtime state management

7. **X-Ray Transaction Search Config already exists error**:
```
CREATE_FAILED | AWS::XRay::TransactionSearchConfig | bedrockagentcoreru...archConfig2B8A09A6
Resource handler returned message: "null" (HandlerErrorCode: AlreadyExists)
```

**Cause**: The X-Ray TransactionSearchConfig resource is limited to one per AWS account per region. This error occurs when:
- Another AgentCore runtime has already created this resource in the same account/region
- Another AWS service or deployment has configured X-Ray transaction search
- You're deploying multiple agentic applications in the same region

**Solution**: Add `enableTransactionSearch: false` to your runtime configuration in `bedrock-agentcore-runtime/bedrock-agentcore-runtime.yaml`:

```yaml
agentRuntimeName: helloAgentRuntime
enableTransactionSearch: false  # Add this line
description: "Hello Agent Runtime"
agentRuntimeArtifact:
  containerConfiguration:
    codePath: ./agent_core_code
    platform: linux/arm64
# ... rest of configuration
```

***

## Next Steps

After deploying this sample agentic application:

1. **Customize the Agent Logic**: Modify `agent.py` to implement your specific use case
2. **Add Business Logic**: Integrate with your existing systems and data sources
3. **Implement Tools**: Add custom tools and capabilities to extend agent functionality
4. **Scale the Solution**: Deploy multiple agent runtimes for different use cases
5. **Monitor & Optimize**: Use CloudWatch metrics and logs to optimize performance
6. **Secure for Production**: Review and enhance security controls for your production environment

For more information on building agentic applications, see:
- [Amazon Bedrock AgentCore Documentation](https://docs.aws.amazon.com/bedrock-agentcore/)
- [Strands Framework Documentation](https://github.com/awslabs/strands)
- [MDAA Documentation](../../README.md)

