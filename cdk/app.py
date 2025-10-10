#!/usr/bin/env python3
import os

import aws_cdk as cdk

from lib.stacks.network_stack import NetworkStack
from lib.stacks.app_stack import AppStack
from lib.stacks.web_stack import WebStack
from lib.stacks.database_stack import DatabaseStack

app = cdk.App()

# Network Layer (VPC + Subnets)
network_stack = NetworkStack(app, "NetworkStack")

# Web Layer (ALB in public subnet)
web_stack = WebStack(
    app,
    "WebStack",
    network_stack=network_stack
)

# Database Layer (RDS in private isolated subnet)
database_stack = DatabaseStack(
    app,
    "DatabaseStack",
    network_stack=network_stack
)

# Application Layer (ASG in private subnet with egress)
app_stack = AppStack(
    app,
    "AppStack",
    network_stack=network_stack,
    alb_sg=web_stack.alb_security_group,
    app_target_group=web_stack.app_target_group,
    # rds_security_group=None,
    # rds_secret=None
)

web_stack.add_dependency(network_stack)
app_stack.add_dependency(network_stack)
database_stack.add_dependency(network_stack)


app_stack.link_database(
    rds_security_group=database_stack.rds_security_group,
    rds_secret=database_stack.rds_secret
)

app.synth()
