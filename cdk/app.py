#!/usr/bin/env python3
import os

import aws_cdk as cdk

from cdk_deploy.stacks.network_stack import NetworkStack


app = cdk.App()

network_stack = NetworkStack(app, "NetworkStack")

app.synth()
