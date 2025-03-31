### CrashPlan Labs Tools

Tools is a repo for all sorts of resources that can make working with CrashPlan easier. Much of the items in this repo will be related to the API, but it's a more general place for useful pieces of tooling.

PushRestore.ps1
- Script to automate kicking off a push restore. See the specific push_restore readme for more information.

customize_email_templates.ps1
- Script to help manage custom email templates, and setting up new ones.
- Email Customization is documented in depth on this page.
- https://support.crashplan.com/hc/en-us/articles/9057161536781--Customize-email-templates

Exclusions
exclusions.txt is a list of our recommended exclusions.

API Authenticaion 
- Collection of scripts to help when using the API. Covers authentication and generating a bearer token for both basic auth users, that need a 2fa code and CrashPlan API clients. 
- Powershell scripts support both powershell core and 5.1
- Shell Scripts work on macOS and linux, and with shell and zsh.