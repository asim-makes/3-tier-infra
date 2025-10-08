#!/usr/bin/env python3
import os

import aws_cdk as cdk

from lib.stacks.network_stack import NetworkStack
from lib.stacks.app_stack import AppStack
from lib.stacks.web_stack import WebStack

app = cdk.App()

network_stack = NetworkStack(app, "NetworkStack")

web_stack = WebStack(app, "WebStack", network_stack=network_stack)

app_stack = AppStack(app,
                     "AppStack",
                     network_stack=network_stack
                     web_stack=web_stack
                    )

app.synth()
