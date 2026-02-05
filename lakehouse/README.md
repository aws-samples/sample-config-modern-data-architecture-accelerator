# Modern Data Architecture/Lake House

This is a sample MDAA Modern Data Architecture/LakeHouse, including S3 Data Lake with LakeFormation fine-grained access controls, a Data Warehouse, and DataOps Crawlers, Jobs, and Workflows (illustrated using New York Taxi Data).

![lakehouse](docs/lakehouse.png)

***

## Deployment Instructions

1. Edit the `mdaa.yaml` to specify an organization name. This must be a globally unique name, as it is used in the naming of all deployed resources, some of which are globally named (such as S3 buckets).

2. If required, edit the `mdaa.yaml` to specify `context:` values specific to your environment.

3. Ensure you are authenticated to your target AWS account and have CDK bootstrapped in your target region.

4. Deploy the architecture:
   ```bash
   npx @aws-mdaa/cli deploy
   ```

***

## Configurations

The sample configurations for this architecture are provided below.

### Config Directory Structure

```bash
lakehouse
│   mdaa.yaml
│   tags.yaml
│   roles.yaml
│
└───datalake
│    └───datalake.yaml
│    └───athena.yaml
│
└───datawarehouse
│    └───datawarehouse.yaml
│
└───nyc_dataops
│    └───project.yaml
│    └───crawler.yaml
│    └───jobs.yaml
│    └───jobs_src
│    └───workflow.yaml
│
└───sample_data   # There are 3 types of data in this folder: trip data, payment, and vendor. 
```

***

### mdaa.yaml

This configuration specifies the global, domain, env, and module configurations required to configure and deploy this sample architecture.

*Note* - Before deployment, populate the [mdaa.yaml](mdaa.yaml) with appropriate organization and context values for your environment

### tags.yaml

This [configuration](tags.yaml) specifies the tags to be applied to all deployed resources.

***

### roles.yaml

This [configuration](roles.yaml) will be used by the MDAA Roles module to deploy IAM roles and Managed Policies required for this sample architecture.

***

### datalake/datalake.yaml

This [configuration](datalake/datalake.yaml) will be used by the MDAA S3 Data Lake module to deploy KMS Keys, S3 Buckets, and S3 Bucket Policies required for the basic Data Lake.

***

### datalake/athena.yaml

This [configuration](datalake/athena.yaml) will create a standalone Athena Workgroup which can be used to securely query the data lake. Note that Glue Databases and Tables will likely need to be manually created on top of the S3 Data Lake in order to query data.

***

### datalake/lakeformation-settings.yaml

This [configuration](datalake/lakeformation-settings.yaml) will be used by the MDAA LakeFormation Settings module to ensure LakeFormation is configured to not automatically create IAMAllowPrincipals grants on new Glue databases and tables, as well as to grant LakeFormation administrative access to specified principals.

***

### datawarehouse/datawarehouse.yaml

This [configuration](datawarehouse/datawarehouse.yaml) will be used by the MDAA Data Warehouse module to deploy a Redshift cluster.

***

### nyc_dataops/project.yaml

This [configuration](nyc_dataops/project.yaml) will be used by the MDAA Data Ops Project module to deploy all resources required to support Data Ops activities.

***

### nyc_dataops/crawler.yaml

This [configuration](nyc_dataops/crawler.yaml) will be used by the MDAA Data Ops Crawler module to deploy Glue Crawlers for crawling/discovering data in the data lake.

***

### nyc_dataops/jobs.yaml

This [configuration](nyc_dataops/jobs.yaml) will be used by the MDAA Data Ops Jobs module to deploy Glue Jobs for processing data in the data lake.

***

### nyc_dataops/workflow.yaml

This [configuration](nyc_dataops/workflow.yaml) will be used by the MDAA Data Ops Workflows module to deploy Glue Workflows for orchestrating Crawlers and Jobs.

## DataOps Design

![dataops](docs/dataops.png)

Following is the general sequence of operations in the DataOps design.

- Csv file is written to the S3 Data Lake raw bucket in the `data/nyc_taxi/...` folder
- S3 eventbridge notification will trigger and event to start 3 Glue workflows:
  - Trip Facts Workflow (`...fact_trp_wf`)
  - Vendor Dimension Workflow (`...dim_vndr_wf`)
  - Payment Dimension Workflow (`...dim_pymnt_wf`)
- Each Glue Workflow will run following tasks in sequence:-
  - Glue Crawler to define/update table based on newly uploaded data. If crawler succeeds, Glue Workflow will go to next step.
  - Glue Jobs converts csv file to parquet and adds partition to standardized location in Data Lake bucket. If Job succeeds, Glue Workflow moves to next step.
  - Glue Job transforms the data and stores it in the curated location in the Data Lake bucket. If the Job succeeds, the Glue Workflow moves to the next step.
  - Glue Job loads the data into the Redshift cluster.

## Usage Instructions

Once the MDAA deployment is complete, follow the following steps to interact with the data lake.

1. Assume the `data-admin` role created by the MDAA deployment. This role is configured with AssumeRole trust to the local account by default. Note that this role is the only role configured with write access to the data lake. All other roles (including existing administrator roles in the account) will be denied write access.

2. Upload `./sample_data/nyc_taxi` folder and contents to `<raw_bucket>/data/nyc_taxi`. This will trigger the 3 Glue Workflows.

3. Monitor the Glue Workflow executions in the Glue console.

4. Once the workflows complete, the Redshift tables can be queried using Redshift Query Editor:
   a. Connect using `Temporary Credentials`, with Database name `default_db` and Database user `admin`. The `data-admin` IAM role has access to create temporary cluster credentials for the Redshift `admin` user.
   b. Optionally, create named Redshift users for users of the `data-user` role to connect with. This Redshift username will need to match the Role Session Name of their federated or assumed role session. 

      For Example, for an assumed-role arn of: `arn:aws:sts::<account>:assumed-role/sample-org-lakehouse-dev-shared-roles-data-user/some-role-session-name`
      The Redshift user should be created as: `create user "some-role-session-name" password DISABLE`

5. The `data-user` role should have access to view and query the raw, standardized, and curated databases/tables in Athena.

### Sample Data Compatibility

Only 2020 New York yellow taxi data is compatible with the Glue job code in this data pipeline because the job code is defined based on this data schema.
In the sample data folder, only 2 months of trip data are available. If you need more data, copy it from the `s3://nyc-tlc/trip data/` S3 bucket.

Run the below command to list all the files compatible with this data pipeline.

```bash
aws s3 ls --no-sign-request "s3://nyc-tlc/trip data/" | grep "yellow_tripdata_2020-*"
```
