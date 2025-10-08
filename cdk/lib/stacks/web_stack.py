from aws_cdk import Stack
from constructs import Construct
from aws_cdk import aws_ec2 as ec2, aws_ssm as ssm
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

        self.alb_resources = self.alb_construct


