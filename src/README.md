# Resharper Code CleanUp Task

Based on [ReSharper Command Line Tools](https://www.jetbrains.com/help/resharper/ReSharper_Command_Line_Tools.html). Cleans up and formats code during build automatically. Can be used in Pull Request validation pipelines to make sure your project's code is always up to standards. 

Suggested use case:
* Run Code Clean Up in Pull Request Validation build
* Format and clean up only modified files
* If some code was modified by the tool, check in all the change to the PR branch and re-run the build.

### Legal
This extension is provided as-is, without warranty of any kind, express or implied. Resharper is a registered trademark of JetBrains and the extension is produced independently of JetBrains.