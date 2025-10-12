from aws_cdk import (
    aws_ec2 as ec2,
    aws_ssm as ssm,
    aws_iam as iam,
    aws_elasticloadbalancingv2 as elbv2,
    aws_secretsmanager as secretsmanager,
    Stack
)
from constructs import Construct
from lib.constructs.asg_construct import AsgConstruct
from lib.stacks.network_stack import NetworkStack
from lib.constructs.rds_construct import RdsConstruct

class AppStack(Stack):
    def __init__(self,
                 scope: Construct,
                 id: str,
                 network_stack: NetworkStack,
                 alb_sg: ec2.ISecurityGroup,
                 app_target_group: elbv2.ApplicationTargetGroup,
                 # rds_security_group: ec2.ISecurityGroup,
                 # rds_secret: secretsmanager.ISecret,
                 **kwargs):
        super().__init__(scope, id, **kwargs)

        self.vpc: ec2.Vpc = network_stack.vpc

        # ALB Security Group
        self.alb_sg = alb_sg
        self.app_target_group = app_target_group

        # Create RDS in the same stack due to circular dependency issue
        self.rds_construct = RdsConstruct(
            self,
            "RDSInstance",
            vpc=self.vpc
        )

        # CloudWatch Agent configuration
        agent_config_json = """
        {
            "metrics": {
                "append_dimensions": {
                    "InstanceId": "${aws:InstanceId}"
                },
                "metrics_collected": {
                    "cpu": {
                        "measurement": [
                            "cpu_usage_idle",
                            "cpu_usage_iowait",
                            "cpu_usage_user",
                            "cpu_usage_system"
                        ],
                        "metrics_collection_interval": 60
                    }
                }
            },
            "logs": {
                "logs_collected": {
                    "files": {
                        "collect_list": [
                            {
                                "file_path": "/var/log/messages",
                                "log_group_name": "/ec2/messages",
                                "log_stream_name": "{instance_id}"
                            },
                            {
                                "file_path": "/var/log/syslog",
                                "log_group_name": "/ec2/syslog",
                                "log_stream_name": "{instance_id}"
                            }
                        ]
                    }
                }
            }
        }
        """

        ssm_param = ssm.StringParameter(
            self, "CloudWatchAgentConfig",
            parameter_name="/CloudWatchAgent/EC2/Config",
            string_value=agent_config_json
        )

        user_data = ec2.UserData.for_linux()

        # General bootstrapping commands
        user_data.add_commands(
            "yum update -y",
            "yum install telnet -y",
            "yum install nc -y",

            # Install nginx
            "amazon-linux-extras install nginx1 -y",

            # Change the listening to port from 80 to 8080
            "sed -i 's/listen       80/listen       8080/' /etc/nginx/nginx.conf",
            "sed -i 's/listen       \[::\]:80/listen       \[::\]:8080/' /etc/nginx/nginx.conf",

            # Start and enable nginx
            "systemctl start nginx",
            "systemctl enable nginx",

            # Install cloudwatch agent
            "yum install -y amazon-cloudwatch-agent",
            f"/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c ssm:{ssm_param.parameter_name} -s"
        )

        # RDS bootstrapping commands
        rds_endpoint = self.rds_construct.rds_instance.db_instance_endpoint_address
        rds_port = self.rds_construct.rds_instance.db_instance_endpoint_port

        # RDS Connectivity Script
        rds_check_script = f"""
            cat << 'EOF' > ~/rds_connection_check.sh
            #!/bin/bash
            RDS_ENDPOINT="{rds_endpoint}"
            RDS_PORT="{rds_port}"
            LOG_FILE="/var/log/rds_connectivity.log"

            echo "Starting continuous connectivity check to \$RDS_ENDPOINT on port \$RDS_PORT..." > \$LOG_FILE

            while true; do
                TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
                RESOLVED_IP=$(dig +short \$RDS_ENDPOINT | head -n 1)

                # Note: 'nc' is already installed via 'yum install nc -y' earlier
                nc -zw1 \$RDS_ENDPOINT \$RDS_PORT 

                if [ $? -eq 0 ]; then
                    STATUS="Connected"
                else
                    STATUS="Failed"
                fi

                echo "\$TIMESTAMP | IP Resolved: \$RESOLVED_IP | Status: \$STATUS" | tee -a \$LOG_FILE
                sleep 1
            done
            EOF

            chmod +x ~/rds_check.sh
            """
        
        user_data.add_commands(rds_check_script)

        self.asg_construct = AsgConstruct(
            self,
            "AsgConstruct",
            vpc=self.vpc,
            alb_sg=self.alb_sg,
            app_target_group=app_target_group,
            user_data=user_data,
            db_sg=self.rds_construct.rds_security_group,
            rds_secret=self.rds_construct.rds_secret
        )

        self.asg_security_group = self.asg_construct.asg_sg

        self.rds_construct.rds_security_group.add_ingress_rule(
            peer=self.asg_security_group,
            connection=ec2.Port.tcp(5432),
            description="Allow postgres connection from application servers"
        )
