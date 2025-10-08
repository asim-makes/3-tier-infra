from aws_cdk import Stack
from constructs import Construct
from aws_cdk import aws_ec2 as ec2, aws_ssm as ssm
from lib.constructs.vpc_construct import VpcConstruct
from lib.stacks.network_stack import NetworkStack


class AppStack(Stack):
    def __init__(self, scope: Construct, id: str, network_stack: NetworkStack, **kwargs):
        super().__init__(scope, id, **kwargs)

        self.vpc: ec2.vpc = network_stack.vpc

        self.alb_sg = ec2.SecurityGroup(
            self, "AlbSecurityGroup",
            vpc=self.vpc,
            description="Security Group for the Application Load Balancer"
        )

        self.db_sg = ec2.SecurityGroup(
            self, "DatabaseSecurityGroup",
            vpc=self.vpc,
            description="Security Group for the RDS Database"
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

        ssm.string_parameter(
            self, "CloudWatchAgentConfig",
            parameter_name="/CloudWatchAgent/EC2/Config",
            string_value=agent_config_json
        )

        user_data = ec2.UserData.for_linux()
        user_data.add_commands(
            "yum update -y",
            "yum install -y amazon-cloudwatch-agent",
            f"/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c ssm:{ssm_param.parameter_name} -s"
        )

        self.asg_construct = AsgConstruct(
            self,
            "AsgConstruct",
            vpc=self.vpc,
            alb_sg=self.alb_sg,
            database_sg=self.db_sg,
            user_data=user_data
        )
