from aws_cdk import (
    aws_ec2 as ec2,
    aws_ssm as ssm,
    aws_elasticloadbalancingv2 as elbv2,
    aws_secretsmanager as secretsmanager,
    Stack
)
from constructs import Construct
from lib.constructs.asg_construct import AsgConstruct
from lib.stacks.network_stack import NetworkStack


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

        # Database configuration
        self._db_sg = None
        self._rds_secret = None

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
            app_target_group=app_target_group,
            user_data=user_data,
        )

        self.asg_security_group = self.asg_construct.asg_sg

    def link_database(self, rds_security_group: ec2.ISecurityGroup, rds_secret: secretsmanager.ISecret):

        self.asg_security_group.add_egress_rule(
            peer=rds_security_group,
            connection=ec2.Port.tcp(5432),
            description="Allow connection to RDS"
        )

        rds_secret.grant_read(self.asg_construct.auto_scaling_group.role)
