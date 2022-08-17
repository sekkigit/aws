AWS DevOps IaC Assessment
 
 
The script below is an AWS CloudFormation yaml template that you can use to create the requested infrastructure in an AWS account. 
Feel free to use any AWS account for it. The template will build a simple network infrastructure where we have a load balancer with autoscaling group, a single server and a Redis database. 
You can freely customize the AMI instances to your work environment (Linux / Windows). 
 
The following two modifications need to be done on the infrastructure:
  
1. Find errors or misconfigured things in the infrastructure, guided by the best practice standards. Describe the found errors and correct them in the script itself.
 
2. Upgrade the script with the RDP option to the server and install the IIS component on the server using IaC practice 
(if you come from the Linux world, feel free to create the option with SSH connection and Nginx base installation). 
 
Please send us back the revised and updated template as a solution to the task.

Yaml template can be downloaded here:

