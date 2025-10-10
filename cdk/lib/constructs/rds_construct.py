from aws_cdk import (
    aws_ec2 as ec2,
    aws_rds as rds,
    Stack
)
from constructs import Construct

class RdsConstruct(Construct):

    @property
    def rds_security_group(self) -> ec2.SecurityGroup:
        return self._rds_security_group
    
    def __init__(self, scope:Construct, id:str, **kwargs) -> None:
        super().__init__(scope, id, **kwargs)

        self.rds_instance = rds.DatabaseInstance(
            self,
            "RDSInstance",
            engine=rds.DatabaseInstanceEngine.postgres(version=rds.PostgresEngineVersion.VER_16_3),
            instance_type=ec2.InstanceType.of(ec2.InstanceClass.Burstable4, ec2.InstanceSize.micro),
            vpc=vpc,
            allocated_storage=20
        )