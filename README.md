# MDAA Sample Configurations

This repository contains sample configuration files for deploying common data analytics architectures using the Modern Data Architecture Accelerator (MDAA). These samples provide working examples to help you get started with MDAA.

For the complete MDAA source code, documentation, and additional configurations, visit [https://github.com/aws/modern-data-architecture-accelerator](https://github.com/aws/modern-data-architecture-accelerator).

## Contents

- [lakeformation_datalake](lakeformation_datalake/) - Data lake with fine-grained access control using Lake Formation
- [basic_datawarehouse](basic_datawarehouse/) - Standalone Redshift data warehouse
- [lakehouse](lakehouse/) - Complete lakehouse with data lake, Redshift, and DataOps pipelines
- [governed_lakehouse](governed_lakehouse/) - Enterprise lakehouse with comprehensive governance
- [agentic_app](agentic_app/) - Agentic AI application with tool use capabilities

## Getting Started

To get started with these sample configurations, ensure you have:

1. An AWS account with appropriate permissions
2. AWS CDK bootstrapped in your target account and region
3. Node.js 22.x and npm 8.x or greater installed

Then navigate to one of the sample folders above. Detailed instructions are provided in each folder's README.

### Basic Deployment

```bash
# Navigate to a sample configuration directory
cd sample_configs/basic_datalake

# Edit the configuration with your organization name
vi mdaa.yaml

# Preview the stacks that will be deployed
npx @aws-mdaa/cli ls

# Deploy the architecture
npx @aws-mdaa/cli deploy
```

Alternatively, you can install the CLI globally for shorter commands:

```bash
npm install -g @aws-mdaa/cli
mdaa ls
mdaa deploy
```

## Enable AWS IAM Permissions

The AWS identity you use must have sufficient IAM permissions to deploy MDAA resources. To grant the necessary permissions:

1. Open the AWS IAM Console
2. Find your Role or User
3. Select Add Permissions > Create Inline Policy, open the JSON editor and add appropriate permissions for the services you're deploying (S3, Glue, Redshift, SageMaker, etc.)

For more information on MDAA security and compliance, check out the [Security Documentation](https://github.com/aws/modern-data-architecture-accelerator/blob/main/SECURITY.md).

## Configuration Structure

Each sample typically includes:

- `mdaa.yaml` - Main configuration file defining modules and deployment settings
- `tags.yaml` - Resource tagging configuration
- Module-specific YAML files for datalake, dataops, analytics, etc.
- `README.md` - Sample-specific documentation with architecture diagrams

## Contributing

We welcome community contributions! Please see [CONTRIBUTING](CONTRIBUTING.md) for guidelines.

## License

This library is licensed under the MIT-0 License. See the LICENSE file.
