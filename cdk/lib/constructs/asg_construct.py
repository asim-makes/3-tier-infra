from aws_cdk import (
    aws_ec2 as ec2,
    aws_autoscaling as autoscaling,
    aws_iam as iam,
)
from constructs import Construct

class AsgConstruct(Construct):
    def __init__(self, scope:Construct, id:str, vpc:ec2.Vpc, alb_sg: ec2.SecurityGroup, db_sg: ec2.SecurityGroup, user_data:str, **kwargs) -> None:
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


        # Create the security group
        self.asg_sg = ec2.SecurityGroup(
            self,
            "ASGSecurityGroup",
            vpc=vpc,
            description="Security Group for ASG in private subnets",
            allow_all_outbound=True
        )

        # Ingress and Outgress rules
        self.asg_sg.add_ingress_rule(
            peer=alb_sg,
            connection=ec2.Port.tcp(8080),
            description="Allow traffic from ALB on app port 8080"
        )

        self.asg_sg.add_egress_rule(
            peer=db_sg,
            connection=ec2.Port.tcp(3306),
            description="Allow connection to RDS"
        )

        self.asg_sg.add_egress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(443),
            description="Allow HTTPS outbound for updates and API calls via NAT Gateway"
        )


        # ASG section
        amzn_linux = ec2.MachineImage.latest_amazon_linux2()
        instance_type = ec2.InstanceType("t3.micro")

        subnets_az1 = vpc.select_subnets(
                subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                availability_zones=[vpc.availability_zones[0]]
        )

        subnets_az2 = vpc.select_subnets(
                subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                availability_zones=[vpc.availability_zones[1]]
        )

        asg_az1 = autoscaling.AutoScalingGroup(
                self,
                "ASG_AZ1",
                instance_type=instance_type,
                machine_image=amzn_linux,
                role=instance_role,
                security_groups=[self.asg_sg],
                vpc_subnets=subnets_az1,
                min_capacity=1,
                max_capacity=2,
                **user_data=user_data**,
                **health_check=autoscaling.HealthCheck.elb(grace=core.Duration.minutes(5))**
        )

        asg_az1.scale_on_cpu_utilization(
            "TargetTrackingCPU",
            target_utilization_percent=60
        )

        asg_az1.attach_to_application_target_group(app_target_group)

        asg_az2 = autoscaling.AutoScalingGroup(
                self,
                "ASG_AZ2",
                isntance_type=instance_type,
                machine_image=amzn_linux,
                role=instance_role,
                security_groups=[self.asg_sg],
                vpc_subnets=subnets_az2,
                min_capacity=1,
                max_capacity=2,
                **user_data=user_data**,
                **health_check=autoscaling.HealthCheck.elb(grace=core.Duration.minutes(5))**
        )

        asg_az2.scale_on_cpu_utilization(
            "TargetTrackingCPU",
            target_utilization_percent=60
        )

        asg_az2.attach_to_application_target_group(app_target_group)
