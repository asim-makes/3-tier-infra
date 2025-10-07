from aws_cdk import Stack
from constructs import Construct
from lib.constructs.vpc_construct import VpcConstruct

class NetworkStack(Stack):
    def __init__(self, scope: Construct, id: str, **kwargs):
        super().__init__(scope, id, **kwargs)

        vpc_name = "3-tier-vpc"
        vpc_cidr = "192.168.0.0/16"
        audit_bucket_name = "portfolio-demo-audit-logs"

        self.vpc_construct = VpcConstruct(
            self, "VpcConstruct",
            vpc_name=vpc_name,
            vpc_cidr=vpc_cidr,
            audit_bucket_name=audit_bucket_name
        )

        self.vpc = self.vpc_construct.vpc
