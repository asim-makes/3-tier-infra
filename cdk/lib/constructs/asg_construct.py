from typing import Optional
from aws_cdk import (
    aws_ec2 as ec2,
    aws_autoscaling as autoscaling,
    aws_elasticloadbalancingv2 as elbv2,
    aws_iam as iam,
    aws_secretsmanager as secretsmanager,
    Duration,
)
from constructs import Construct

class AsgConstruct(Construct):

    @property
    def auto_scaling_group(self) -> autoscaling.AutoScalingGroup:
        return self._asg
    
    def __init__(self,
                scope:Construct,
                id:str,
                *,
                vpc:ec2.Vpc,
                alb_sg: ec2.SecurityGroup,
                app_target_group: elbv2.ApplicationTargetGroup,
                user_data:ec2.UserData,
                db_sg: Optional[ec2.ISecurityGroup] = None,
                rds_secret: Optional[secretsmanager.ISecret] = None,
                **kwargs) -> None:
        super().__init__(scope, id, **kwargs)

        # Define IAM role and permissions
        instance_role = iam.Role(
            self, "ASGInstanceRole",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            description="IAM role for application servers, enabling logging and SSM access"
        )

        # Permission 1: SSM access
        instance_role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name("AmazonSSMManagedInstanceCore")
        )

        # Permission 2: CloudWatch agent
        instance_role.add_managed_policy(
                iam.ManagedPolicy.from_aws_managed_policy_name("CloudWatchAgentServerPolicy")
        )

        # Permission 3: CloudWatch Logs
        instance_role.add_managed_policy(
                iam.ManagedPolicy.from_aws_managed_policy_name("CloudWatchLogsFullAccess")
        )

        # Permission 4: Database Credentials
        if rds_secret is not None:
            rds_secret.grant_read(instance_role)

        # Create the security group
        self.asg_sg = ec2.SecurityGroup(
            self,
            "ASGSecurityGroup",
            vpc=vpc,
            description="Security Group for ASG in private subnets",
            allow_all_outbound=False
        )

        # Ingress and Outgress rules
        self.asg_sg.add_ingress_rule(
            peer=alb_sg,
            connection=ec2.Port.tcp(8080),
            description="Allow traffic from ALB on app port 8080"
        )

        if db_sg is not None:
            self.asg_sg.add_egress_rule(
                peer=db_sg,
                connection=ec2.Port.tcp(5432),
                description="Allow ASG to connect to RDS"
            )

        self.asg_sg.add_egress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(443),
            description="Allow HTTPS outbound for updates and API calls via NAT Gateway"
        )

        # ASG section
        amzn_linux = ec2.MachineImage.latest_amazon_linux2()
        instance_type = ec2.InstanceType("t3.micro")

        all_private_subnets = vpc.select_subnets(
            subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS
        )

        self._asg = autoscaling.AutoScalingGroup(
            self,
            "ApplicationAutoScalingGroup",
            vpc=vpc,
            instance_type=instance_type,
            machine_image=amzn_linux,
            role=instance_role,
            security_group=self.asg_sg,
            vpc_subnets={
                'subnet_type': ec2.SubnetType.PRIVATE_WITH_EGRESS
            },
            min_capacity=2,
            max_capacity=2,
            user_data=user_data,
            health_checks=autoscaling.HealthChecks.ec2(
                grace_period=Duration.minutes(5)
            )
        )

        self._asg.attach_to_application_target_group(app_target_group)

        self._asg.scale_on_cpu_utilization(
            "TargetTrackingCPU",
            target_utilization_percent=60
        )
