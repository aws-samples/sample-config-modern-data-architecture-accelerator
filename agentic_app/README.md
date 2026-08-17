# Agentic Application Sample Configuration

This sample configuration demonstrates building a simple agentic application using MDAA, featuring a custom agent runtime powered by Amazon Bedrock AgentCore. This provides a starting point for customers to build intelligent, autonomous applications that can reason, plan, and execute tasks.

***

## Architecture Overview

This configuration deploys a complete agentic application with:

1. **Custom Agent Runtime**: Containerized agent using the Strands framework for flexible agent logic
2. **Secure Authentication**: JWT-based access control via an Amazon Cognito user pool that MDAA creates and configures, with threat protection, a strong password policy, short-lived tokens, and MFA required. People sign in **interactively in a browser** through Cognito's managed login (hosted UI), which prompts each user to set their password and register a TOTP authenticator on first sign-in, then returns an authorization code to exchange for the token used to invoke the agent
3. **Network Security**: VPC-secured deployment with private subnets
4. **Scalable Infrastructure**: Managed runtime with automatic scaling and high availability
5. **Observability**: CloudWatch logging and metrics, plus ADOT tracing with spans routed to the agent's own log group, so span content inherits its CMK encryption, retention, and PII masking
6. **Operational Alerting**: CloudWatch alarms on error rate and throttling, plus EventBridge rules on security-relevant AgentCore events, notifying a CMK-encrypted SNS topic
7. **API Access**: Runtime endpoint for programmatic agent invocation
8. **IAM Security**: Least-privilege roles with appropriate permissions

***

## Deployment Instructions

### Step-by-Step Deployment

1. Edit the `mdaa.yaml` to specify an organization name. This must be a globally unique name, as it is used in the naming of all deployed resources.

2. Configure Context Values - Update the `mdaa.yaml` file under the `context:` section with your environment-specific values:
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
├── mdaa.yaml                          # Main orchestration config — also selects the auth path
├── tags.yaml                          # Resource tagging
├── bedrock-agentcore-runtime/
│   ├── runtime-base.yaml              # Shared runtime settings (not deployable alone)
│   ├── runtime-jwt.yaml               # Cognito JWT / OAuth inbound — the deployed path
│   ├── runtime-sigv4.yaml             # SigV4 (IAM) inbound — alternative, not deployed
│   └── agent_core_code/
│       ├── agent.py                   # FastAPI agent server
│       ├── Dockerfile                 # Container image definition
│       ├── pyproject.toml             # Python dependencies
│       ├── uv.lock                    # Dependency lock file
│       └── .python-version            # Python version specification
├── roles/
│   ├── roles.yaml                     # Audit reader, agent log reader
│   └── roles-callers.yaml             # Caller roles — SigV4 path only, not deployed
├── audit/audit.yaml                   # Audit bucket + CMK the trail delivers to
├── audit-trail/audit-trail.yaml       # CloudTrail trail with AgentCore data events
├── security-best-practices/           # Security guidance, split by who has to act
│   ├── YOUR-RESPONSIBILITIES.md       #   what you do out of band
│   ├── CONFIGURABLE-CONTROLS.md       #   what you get by setting a property
│   ├── BUILT-IN-CONTROLS.md           #   what MDAA applies unconditionally
│   └── policies/                      #   SCP and resource-policy JSON
└── lza/README.md                      # Applying the org-level controls with LZA
```

### Key Configuration Files

#### mdaa.yaml - Main Configuration
**⚠️ Required Changes Before Deployment:**
- `organization`: Must be globally unique (used in resource naming)
- `vpc_id`: VPC containing the subnets below
- `security_group_id`: Security group for the runtime
- `subnet_id_1`, `subnet_id_2`: Private subnet IDs
- `notification_email`: Address to subscribe to the alarm/alert SNS topic

```yaml
region: default
organization: <org>  # CHANGE THIS

context:
  vpc_id: <>                    # CHANGE THIS
  security_group_id: <>         # CHANGE THIS
  subnet_id_1: <>               # CHANGE THIS
  subnet_id_2: <>               # CHANGE THIS
  notification_email: <>        # CHANGE THIS

domains:
  governance:            # deploys first — the 'ai' domain reads its SSM parameters
    environments:
      dev:
        modules:
          roles:
            module_path: "@aws-mdaa/roles"
            module_configs:
              - ./roles/roles.yaml
              # - ./roles/roles-callers.yaml    # SigV4 path only
          audit:
            module_path: "@aws-mdaa/audit"
            module_configs:
              - ./audit/audit.yaml

  ai:
    environments:
      dev:
        modules:
          agent-core-app:
            module_path: "@aws-mdaa/bedrock-agentcore-runtime"
            module_configs:
              - ./bedrock-agentcore-runtime/runtime-base.yaml
              - ./bedrock-agentcore-runtime/runtime-jwt.yaml
              # - ./bedrock-agentcore-runtime/runtime-sigv4.yaml
          audit-trail:
            module_path: "@aws-mdaa/audit-trail"
            module_configs:
              - ./audit-trail/audit-trail.yaml
```

**The runtime config is layered.** `runtime-base.yaml` holds everything both inbound-auth paths share; exactly one auth layer goes on top, and MDAA deep-merges them left to right. The layer file *is* the difference between the two paths, so to see what changes, read the layer rather than diffing two long configs.

To use SigV4 (IAM) inbound instead of Cognito JWT: swap `runtime-jwt.yaml` for `runtime-sigv4.yaml`, and uncomment `roles/roles-callers.yaml` at the same time. Never both auth layers — the presence of an authorizer block is what selects JWT.

#### Key Module Configurations

- **runtime-base.yaml**: Container settings, network configuration, log protection, alarms, and EventBridge rules — everything both auth paths share
- **runtime-jwt.yaml**: The Cognito JWT authorizer, added on top of the base. This is the deployed path
- **runtime-sigv4.yaml**: The SigV4 alternative — sets the VPC endpoint policy's allowed principals and, by omitting an authorizer, selects IAM inbound auth
- **roles/roles.yaml**: Audit-bucket reader, plus a log reader denied `logs:Unmask` so PII masking holds for it
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
- **Telemetry**: `aws-opentelemetry-distro>=0.18.0` in `pyproject.toml`, with the Dockerfile `CMD` running the server under `opentelemetry-instrument`

> **The `opentelemetry-instrument` wrapper in the Dockerfile `CMD` is what produces spans.** It auto-instruments Strands and the HTTP stack at startup. Remove it — or drop the ADOT dependency — and you are left with a **working agent that emits no telemetry**: it deploys cleanly, reports healthy, serves requests, and appears in the CloudWatch console identically to an agent receiving no traffic. There is no error to alert on.
>
> The `>=0.18.0` floor matters separately: below it, ADOT ignores the span destination and delivers spans to the shared `aws/spans` log group instead of this agent's own protected one.

### Security & Compliance

The deployment implements:
- **Authentication**: JWT-based authentication via Amazon Cognito, with interactive browser sign-in through managed login and TOTP MFA required of every user
- **Authorization**: Fine-grained IAM permissions for runtime execution
- **Encryption**: Data encryption in transit and at rest
- **Network Isolation**: VPC deployment with private subnets
- **Audit Logging**: CloudWatch logs for all agent interactions

These are the controls this configuration deploys. The organization- and account-level controls that should surround them before a production deployment — SCP templates, CloudTrail data events, the inbound authorization evaluation order, a pre-production checklist, and cross-account observability — are documented in [security-best-practices/YOUR-RESPONSIBILITIES.md](security-best-practices/YOUR-RESPONSIBILITIES.md).

Two of them are worth knowing now, because they change what you get from this configuration:

- **CloudTrail data events are off by default**, so `InvokeAgentRuntime` calls are not recorded and the `auth-failure` EventBridge rule this config deploys will not match anything. See step 7 below, and [section 3](security-best-practices/YOUR-RESPONSIBILITIES.md#3-cloudtrail-data-events).
- **SCPs do not restrict OAuth/JWT callers.** This configuration uses Cognito JWT inbound auth, so its resource-based policy is the perimeter, not any org-level guardrail. See [section 4](security-best-practices/YOUR-RESPONSIBILITIES.md#4-evaluation-order).

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

### 2. Create Cognito User

MDAA created the user pool as part of the deployment and published its identifiers to SSM,
so read them from there rather than looking them up in the console. The pool starts empty:
`selfSignUpEnabled` is false, so an administrator creates users.

```bash
COGNITO_PATH="/${ORG}/${DOMAIN}/${MODULE_NAME}/cognito"

USER_POOL_ID=$(aws ssm get-parameters-by-path \
  --path ${COGNITO_PATH} \
  --recursive \
  --region ${REGION} \
  --query "Parameters[?ends_with(Name, '/user-pool-id')].Value | [0]" \
  --output text)

COGNITO_CLIENT_ID=$(aws ssm get-parameters-by-path \
  --path ${COGNITO_PATH} \
  --recursive \
  --region ${REGION} \
  --query "Parameters[?ends_with(Name, '/client-id')].Value | [0]" \
  --output text)

echo "User Pool: ${USER_POOL_ID}  Client: ${COGNITO_CLIENT_ID}"

# The username must be an email address: the pool signs in by email alias
# (UsernameAttributes: ['email']), so Cognito rejects a non-email username with
# "Username should be an email."
#
# The password is temporary, and must satisfy the pool's policy: 8+ characters with
# at least one uppercase, one lowercase, one digit, and one symbol. You will be asked
# to replace it during the browser sign-in in the next step, which is where the user
# chooses a password only they know.
USERNAME="testuser@example.com"
TEMP_PASSWORD="TempPass1@"

aws cognito-idp admin-create-user \
 --user-pool-id ${USER_POOL_ID} \
 --username ${USERNAME} \
 --temporary-password ${TEMP_PASSWORD} \
 --message-action SUPPRESS \
 --region ${REGION}
```

`--message-action SUPPRESS` stops Cognito emailing the invitation, since `testuser@example.com` is not a real mailbox. Drop it when you create a user with an address that is.

### 3. Sign In Through Managed Login and Obtain a Token

The runtime config sets `hostedUi`, so this pool has a Cognito-hosted sign-in page and the app client uses the **authorization code grant**: a person authenticates in a browser and the browser is redirected back with a short-lived `code` that you exchange for tokens. There is deliberately no single-API-call alternative — configuring `hostedUi` disables the plaintext-password auth flow, and this sample requires MFA, which needs a human present to enrol an authenticator.

Build the sign-in URL:

```bash
# The hosted-UI domain prefix. Published to SSM only because `hostedUi` is configured.
COGNITO_DOMAIN=$(aws ssm get-parameters-by-path \
  --path ${COGNITO_PATH} \
  --recursive \
  --region ${REGION} \
  --query "Parameters[?ends_with(Name, '/domain')].Value | [0]" \
  --output text)

AUTH_BASE="https://${COGNITO_DOMAIN}.auth.${REGION}.amazoncognito.com"

# Must match a URL in the runtime config's hostedUi.callbackUrls exactly, here and in
# the token exchange below — Cognito compares it as a string in both requests.
REDIRECT_URI="http://localhost:8000/callback"

# PKCE (RFC 7636). Cognito accepts a code grant without it, but this app client is
# public (no client secret), so the verifier is the only thing proving that whoever
# redeems the code is whoever started the sign-in. Cognito supports S256 only.
#
# The `state` and `nonce` parameters are omitted only because you are driving this by
# hand and there is no application to validate them against. A real front end should
# send both: `state` is its CSRF defence on the redirect, `nonce` its replay defence
# on the ID token.
CODE_VERIFIER=$(openssl rand -base64 60 | tr -d '\n=' | tr '/+' '_-')
CODE_CHALLENGE=$(printf '%s' "${CODE_VERIFIER}" | openssl dgst -sha256 -binary | base64 | tr -d '\n=' | tr '/+' '_-')

echo "${AUTH_BASE}/oauth2/authorize?response_type=code&client_id=${COGNITO_CLIENT_ID}&redirect_uri=${REDIRECT_URI}&scope=openid+profile+email&code_challenge_method=S256&code_challenge=${CODE_CHALLENGE}"
```

Open that URL in a browser and complete the sign-in as the user created above. Managed login walks through the whole first-login sequence:

1. **Sign in** with `testuser@example.com` and the temporary password
2. **Choose a new password** — Cognito requires this because the password was created as temporary
3. **Set up MFA**: scan the QR code with an authenticator app and enter the six-digit code. This step is what `mfa: required` means, and managed login providing it is the reason the sample can keep that default

Cognito then redirects the browser to `http://localhost:8000/callback?code=...`. **Nothing is listening on port 8000, so the browser shows a connection error — that is expected.** The value you need is the `code` query parameter in the address bar. If you would rather not read it off the URL bar, run `python3 -m http.server 8000` in another terminal before signing in; its request log prints the full callback path, code included.

Exchange the code for tokens:

```bash
CODE="<paste the code parameter from the redirect URL>"

TOKENS=$(curl -s -X POST "${AUTH_BASE}/oauth2/token" \
 -H 'Content-Type: application/x-www-form-urlencoded' \
 --data-urlencode "grant_type=authorization_code" \
 --data-urlencode "client_id=${COGNITO_CLIENT_ID}" \
 --data-urlencode "code=${CODE}" \
 --data-urlencode "redirect_uri=${REDIRECT_URI}" \
 --data-urlencode "code_verifier=${CODE_VERIFIER}")

ID_TOKEN=$(printf '%s' "${TOKENS}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id_token"])')
REFRESH_TOKEN=$(printf '%s' "${TOKENS}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["refresh_token"])')
```

If either extraction raises a `KeyError`, run `echo "${TOKENS}"` — Cognito returned an OAuth error object rather than tokens, and the `error` value in it names the cause (see [Troubleshooting](#common-issues)).

The code is **single-use and valid for five minutes**, so exchange it promptly; redeeming it twice returns `invalid_grant`. Pass the **ID token** to the runtime — Cognito puts the app client ID in the ID token's `aud` claim, which is what the runtime's authorizer validates, but in the access token's `client_id` claim instead.

The ID token expires after 15 minutes (`idTokenValidityMinutes`). Mint a fresh one from the refresh token rather than repeating the browser sign-in — refresh tokens last one day:

```bash
ID_TOKEN=$(curl -s -X POST "${AUTH_BASE}/oauth2/token" \
 -H 'Content-Type: application/x-www-form-urlencoded' \
 --data-urlencode "grant_type=refresh_token" \
 --data-urlencode "client_id=${COGNITO_CLIENT_ID}" \
 --data-urlencode "refresh_token=${REFRESH_TOKEN}" \
 | python3 -c 'import json,sys; print(json.load(sys.stdin)["id_token"])')
```

### 4. Invoke the Runtime

Since the runtime is configured for OAuth, you must use an HTTPS request with a Bearer token rather than the AWS CLI:

> **Run this from inside the VPC.** `enforceVpcOnly: true` in the runtime config attaches a resource policy that denies any invocation not arriving through the VPC's `bedrock-agentcore` endpoint, so this request returns `AccessDenied` from a machine on the public internet however valid the token is. Run it from an EC2 instance in `vpc_id`, or from a host with VPN or Direct Connect access into that VPC.
>
> The browser sign-in in step 3 has no such constraint — Cognito's managed login and token endpoint are public — so signing in on your laptop and copying `ID_TOKEN` over to where you run this is fine.

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
- **Spans**: Read the agent's traces from the **`spans` log stream of this agent's own log group** — `/aws/bedrock-agentcore/runtimes/{agentId}-{endpointName}` — not from X-Ray or the shared `aws/spans` group. MDAA routes them there so span content sits inside the same protection boundary as the agent's logs.

Span content is the agent's decision path: prompts, model inputs and outputs, tool arguments, and tool results. Because those spans land in this agent's log group, they are **encrypted with the module's customer-managed KMS key, subject to the 90-day retention set in the runtime config, and PII-masked** by the same CloudWatch Data Protection policy applied to the agent's logs (including the `DriversLicense-US` and `PassportNumber-US` identifiers added there). In the shared `aws/spans` group they would have none of that, and would be readable by anyone with access to that one account-wide group.

To view them:

```bash
aws logs start-query \
  --log-group-name "/aws/bedrock-agentcore/runtimes/${AGENT_ID}-${ENDPOINT_NAME}" \
  --start-time $(($(date +%s) - 3600)) --end-time $(date +%s) \
  --query-string 'fields @timestamp, @message | filter @logStream like /spans/ | sort @timestamp desc' \
  --region ${REGION}
```

Traces also appear in the [CloudWatch GenAI Observability](https://console.aws.amazon.com/cloudwatch/home#gen-ai-observability) console. **If you see no spans at all**, check the container prerequisites before anything else — see the note under [Agent Implementation](#agent-implementation).

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

Deploy the trail with the MDAA audit-trail module, using the worked config in [section 3 of security-best-practices/YOUR-RESPONSIBILITIES.md](security-best-practices/YOUR-RESPONSIBILITIES.md#3-cloudtrail-data-events) — which also covers cost scoping and the `put-event-selectors` path for a trail MDAA does not own.

Two values are specific to this starter kit. Substitute them into the `resourceArns` of both selectors, in place of the generic path that section shows:

```yaml
# Module 'agent-core-app' (mdaa.yaml) + runtime '{{org}}-myAgentRuntimeDev', lowercased.
# Replace <org> with your organization name.
resourceArns:
  - ssm-domain:/agent-core-app/agentruntime/<org>-myagentruntimedev/arn
```

Keep `includeManagementEvents: true` on that trail, or `config-change` goes silent along with every other control plane record.

Verify matches in the EventBridge console before relying on these alerts. To remove the rules instead, delete the `eventBridgeAlerts` block from the runtime config.

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

> **Re-verify span emission after any dependency change.** OpenTelemetry auto-instrumentation works by patching specific internals of specific library versions, so it is version-coupled by nature: upgrading ADOT, Strands, FastAPI, or uvicorn can silently stop spans being produced. Nothing fails, no test catches it, and the agent keeps serving requests normally — the traces simply stop.
>
> After regenerating `uv.lock`, redeploy, invoke the agent, and confirm new events land in the `spans` log stream (see [Monitor Runtime Performance](#5-monitor-runtime-performance)). Keep `aws-opentelemetry-distro` at `>=0.18.0`; dropping below that floor sends spans to the shared `aws/spans` group instead of this agent's protected one.
>
> Keep the Python version aligned across all three places that declare it — the Dockerfile base image, `requires-python` in `pyproject.toml`, and `.python-version`. They are on 3.12 together; a mismatch fails at `uv sync --frozen` during the image build.

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
Integrate with enterprise identity providers (SAML, OIDC) for single sign-on, so users sign in with their corporate credentials instead of a Cognito-local password. This is a `federation` block in the runtime config's `cognito` section — it requires `hostedUi`, which this sample already configures, so the hosted sign-in page starts offering the enterprise provider as soon as it is added. Cognito applies no MFA of its own to federated users, so enforce MFA at that provider and set `mfa: off` here once every user is federated.

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

2. **Sign-in and token exchange failures**:
   - The sign-in URL does not load, or `AUTH_BASE` contains `None`: `COGNITO_DOMAIN` did not resolve. The `domain` SSM parameter exists only when `hostedUi` is configured in the runtime config — check it is still there, and that `USER_POOL_ID` and `COGNITO_CLIENT_ID` also resolved to real values in step 2, since an empty variable produces a confusing failure further along
   - Redirected back with `?error=invalid_request` or a redirect-mismatch error: `REDIRECT_URI` must match one of `hostedUi.callbackUrls` character for character, in both the authorize URL and the token exchange
   - `invalid_grant` from `/oauth2/token`: the code was already redeemed or is more than five minutes old — start a fresh sign-in. Note the browser retains its managed login session, so a repeat authorize request may return a new code without re-prompting
   - `invalid_client` from `/oauth2/token`: `client_id` does not match the app client the code was issued to
   - Stuck at the MFA setup screen: this pool sets `mfa: required`, so enrolling an authenticator is mandatory before any token is issued. To deploy a pool that issues tokens without it — a non-interactive caller, say — set `mfa: optional` in the runtime config

3. **JWT authentication failures at the runtime**:
   - Confirm you passed the **ID token**, not the access token: Cognito puts the client ID in the ID token's `aud` claim, which is what `allowedAudience` validates, but in the access token's `client_id` claim
   - Check the token has not expired — tokens are valid for 15 minutes by default (`idTokenValidityMinutes`). Refresh it as shown at the end of step 3 rather than signing in again
   - If you switched to the `discoveryUrl` option, ensure the URL ends with `/.well-known/openid-configuration`

4. **Container build or deployment failures**:
   - Check that Docker is installed and running on your deployment machine
   - Verify ECR permissions for pushing images
   - Ensure the specified platform (`linux/arm64` or `linux/amd64`) is supported
   - Review CloudWatch logs for container startup errors

5. **Network connectivity issues**:
   - Verify security groups allow outbound traffic to AWS services
   - Ensure subnets have routes to NAT Gateway or VPC endpoints for AWS service access
   - Check that the runtime can reach Bedrock endpoints
   - Verify VPC DNS resolution is enabled

6. **Runtime invocation failures**:
   - `AccessDenied` with a token that authenticated fine: the request did not arrive through the VPC's `bedrock-agentcore` endpoint, which `enforceVpcOnly: true` requires — see the note in [step 4](#4-invoke-the-runtime)
   - Confirm the runtime is in "Active" state in the Bedrock console
   - Verify the runtime endpoint is properly configured
   - Check IAM permissions for the runtime execution role
   - Review CloudWatch logs for detailed error messages

7. **AgentCore runtime-specific issues after successful deployment**:
   - For detailed troubleshooting of runtime behavior, performance, or operational issues, refer to the [Bedrock AgentCore Runtime Troubleshooting Guide](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-troubleshooting.html)
   - This includes guidance on container startup issues, memory/CPU constraints, timeout configurations, and runtime state management

8. **X-Ray Transaction Search Config already exists error**:
```
CREATE_FAILED | AWS::XRay::TransactionSearchConfig | bedrockagentcoreru...archConfig2B8A09A6
Resource handler returned message: "null" (HandlerErrorCode: AlreadyExists)
```

**Cause**: The X-Ray TransactionSearchConfig resource is limited to one per AWS account per region. This error occurs when:
- Another AgentCore runtime has already created this resource in the same account/region
- Another AWS service or deployment has configured X-Ray transaction search
- You're deploying multiple agentic applications in the same region

**Solution**: Add `enableTransactionSearch: false` to your runtime configuration in `bedrock-agentcore-runtime/runtime-base.yaml`:

It is already present as a commented line there — uncomment it:

```yaml
# in bedrock-agentcore-runtime/runtime-base.yaml
enableTransactionSearch: false
```

Traces stay searchable either way: the config is account-wide, so whichever deployment owns it covers the rest.

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
- [MDAA Documentation](https://github.com/aws/modern-data-architecture-accelerator)

