from aws_cdk import (
    Stack,
    aws_ec2 as ec2,
    )
from constructs import Construct
from lib.constructs.alb_construct import AlbConstruct
from lib.stacks.network_stack import NetworkStack


class WebStack(Stack):
    def __init__(self, scope:Construct, id:str, network_stack: NetworkStack, **kwargs):
        super().__init__(scope, id, **kwargs)

        self.vpc: ec2.IVpc = network_stack.vpc

        self.alb_construct = AlbConstruct(
            self,
            "ApplicationLoadBalancerResources",
            vpc=self.vpc
        )

        self.alb_security_group = self.alb_construct.alb_security_group
        self.app_target_group = self.alb_construct.application_target_group