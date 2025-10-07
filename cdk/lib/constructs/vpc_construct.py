from aws_cdk import (
    aws_ec2 as ec2,
    aws_s3 as s3,
    RemovalPolicy
)
from constructs import Construct

class VpcConstruct(Construct):
    def __init__(self, scope: Construct, id: str, *, vpc_name: str, vpc_cidr: str, audit_bucket_name: str):
        super().__init__(scope, id)

        # Import or create the S3 bucket for audit logs
        self.audit_bucket = s3.Bucket(
            self, "AuditBucket", 
            bucket_name=audit_bucket_name,
            versioned=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY
        )

        self.vpc = ec2.Vpc(
            self, "AppVPC",
            vpc_name=vpc_name,
            ip_addresses=ec2.IpAddresses.cidr(vpc_cidr),
            max_azs=2,
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="Public", 
                    subnet_type=ec2.SubnetType.PUBLIC,
                    cidr_mask=22
                ),
                ec2.SubnetConfiguration(
                    name="Compute", 
                    subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                    cidr_mask=20
                ),
                ec2.SubnetConfiguration(
                    name="RDS",
                    subnet_type=ec2.SubnetType.PRIVATE_ISOLATED,
                    cidr_mask=24
                )
            ],
            nat_gateways=1,
            flow_logs={
                'flow-logs-s3': ec2.FlowLogOptions(
                    destination=ec2.FlowLogDestination.to_s3(
                        bucket=self.audit_bucket,
                        key_prefix=f"vpc-logs/{vpc_name}"
                    )
                )
            }
        )