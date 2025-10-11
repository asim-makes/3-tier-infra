#!/usr/bin/env python3
import aws_cdk as cdk
from lib.stacks.network_stack import NetworkStack
from lib.stacks.app_stack import AppStack
from lib.stacks.web_stack import WebStack

app = cdk.App()

# Network Layer
network_stack = NetworkStack(app, "NetworkStack")

# Web Layer
web_stack = WebStack(
    app,
    "WebStack",
    network_stack=network_stack
)

# Application + Database Layer (merged)
app_stack = AppStack(
    app,
    "AppStack",
    network_stack=network_stack,
    alb_sg=web_stack.alb_security_group,
    app_target_group=web_stack.app_target_group
)

web_stack.add_dependency(network_stack)
app_stack.add_dependency(web_stack)

app.synth()