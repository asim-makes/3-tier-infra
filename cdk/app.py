#!/usr/bin/env python3
import os

import aws_cdk as cdk

from lib.stacks.network_stack import NetworkStack
from lib.stacks.app_stack import AppStack

app = cdk.App()

network_stack = NetworkStack(app, "NetworkStack")
app_stack = AppStack(app, "AppStack", network_stack=network_stack)

app.synth()
