from aws_cdk import (
    aws_ec2 as ec2,
    Stack,
)
from constructs import Construct
from lib.stacks.network_stack import NetworkStack
from lib.constructs.rds_construct import RdsConstruct


class DatabaseStack(Stack):

    def __init__(self, scope:Construct, id:str, network_stack:NetworkStack, **kwargs):
        super().__init__(scope, id, **kwargs)

        self.vpc: ec2.IVpc = network_stack.vpc

        self.rds_construct = RdsConstruct(
            self,
            "RDSInstance",
            vpc=self.vpc,
            # app_security_group=app_security_group
        )

        self.rds_security_group = self.rds_construct.rds_security_group
        self.rds_secret = self.rds_construct.rds_secret
