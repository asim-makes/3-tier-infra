from aws_cdk import (
    aws_ec2 as ec2,
    aws_rds as rds,
    aws_secretsmanager as secretsmanager,
)
from constructs import Construct

class RdsConstruct(Construct):

    @property
    def rds_security_group(self) -> ec2.SecurityGroup:
        return self._rds_security_group

    @property
    def rds_secret(self) -> secretsmanager.ISecret:
        return self._rds_secret
    
    def __init__(self, scope:Construct, id:str, *, vpc:ec2.IVpc, **kwargs) -> None:
        super().__init__(scope, id, **kwargs)

        self._rds_security_group = ec2.SecurityGroup(
            self,
            "RDSSecurityGroup",
            vpc=vpc,
            allow_all_outbound=False,
            description="Security Group for RDS"
        )

        # self._rds_security_group.add_ingress_rule(
        #     peer=app_security_group,
        #     connection=ec2.Port.tcp(5432),
        #     description="Allow postgres (5432) connection from EC2 app servers."
        # )

        credentials = rds.Credentials.from_generated_secret("postgresadmin")

        self.rds_instance = rds.DatabaseInstance(
            self,
            "RDSInstance",
            engine=rds.DatabaseInstanceEngine.postgres(version=rds.PostgresEngineVersion.VER_16_3),
            instance_type=ec2.InstanceType("t3.micro"),
            vpc=vpc,
            credentials=credentials,
            allocated_storage=20,
            multi_az=True,
            vpc_subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PRIVATE_ISOLATED),
            # security_groups=[self._rds_security_group],
            publicly_accessible=False
        )

        self._rds_secret = self.rds_instance.secret
