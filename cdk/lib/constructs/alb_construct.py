from aws_cdk import (
    aws_ec2 as ec2,
    aws_elasticloadbalancingv2 as elbv2,
    CfnOutput,
    Stack
)
from constructs import Construct

class AlbConstruct(Construct):

    @property
    def alb_security_group(self) -> ec2.SecurityGroup:
        return self._alb_security_group
    
    @property
    def application_target_group(self) -> elbv2.ApplicationTargetGroup:
        return self._application_target_group

    def __init__(self, scope:Construct, id:str, vpc: ec2.IVpc, **kwargs):
        super().__init__(scope, id, **kwargs)

        self._alb_security_group = ec2.SecurityGroup(
            self,
            "AlbSecurityGroup",
            vpc=vpc,
            allow_all_outbound=True,
            description="Security Group for Application Load Balancer"
        )

        self._alb_security_group.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(80),
            description="Allow HTTP access from anywhere"
        )

        self.alb = elbv2.ApplicationLoadBalancer(
            self,
            "ApplicationLoadBalancer",
            vpc=vpc,
            internet_facing=True,
            security_group=self.alb_security_group,
            vpc_subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PUBLIC)
        )

        self._application_target_group = elbv2.ApplicationTargetGroup(
            self,
            "AppTargetGroup",
            port=8080,
            vpc=vpc,
            protocol=elbv2.ApplicationProtocol.HTTP,
            target_type=elbv2.TargetType.INSTANCE
        )

        self.listener = self.alb.add_listener(
            "HTTPListener",
            port=80,
            default_target_groups=[self._application_target_group]
        )

        CfnOutput(
            self,
            "AppTargetGroupArn",
            value=self._application_target_group.target_group_arn,
            export_name=f"{Stack.of(self).stack_name}-AppTargetGroupArn"
        )