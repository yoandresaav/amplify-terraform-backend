
# Run this project in AWS

### Prerequisites
- AWS account
- AWS CLI
- Terraform

[Install Terraform](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli)

### Steps
1. Create a new IAM user with admin access
2. Configure the AWS CLI with the new user credentials
3. Clone this repository
4. Go to the project directory
5. Run `terraform init`
6. Run `terraform apply`

### Project structure
- `main.tf`: Contains the main configuration of the project
- `pool.tf`: Contains the configuration of Cognito User Pool
- `assembly.tf`: Contains the configuration of the lambda and the API Gateway to join chunks
- `variables.tf`: Contains the variables used in the project
- `outputs.tf`: Contains the outputs of the project
- `Makefile`: Contains the commands to run the project
- `img`: Contains the images used in this file
- `README.md`: Contains the instructions to run the project

### Project overview
![Project overview](./img/project.png)

### Project requirements
![Project requirements](./img/requirements.png)

### High-level overview

![High-level overview](./img/high-level-overview.png)

### Detailed overview
![Detailed overview](./img/detailed-overview.png)



### Notes
- The default region is `us-west-2`. You can change it in the `variables.tf` file.
- Tested using a macOS machine. If you are using Windows, you may need to change the `terraform` command to `terraform.exe` in the `Makefile` file.
