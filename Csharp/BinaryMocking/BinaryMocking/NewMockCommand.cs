using System.Collections.ObjectModel;
using System.Management.Automation;
using System.Reflection;

namespace BinaryMocking
{
    [Cmdlet(VerbsCommon.New, "Mock")]
    public sealed class NewMockCommand : PSCmdlet
    {
        public static string SetupMock { get; set; }

        public static string CreateMock { get; set; } = string.Empty;

        [Parameter(Position = 0, Mandatory = true)]
        public string FunctionName { get; set; }

        [Parameter(Position = 1, Mandatory = true)]
        public ScriptBlock MockWith { get; set; }

        public ScriptBlock ParameterFilter { get; set; } = ScriptBlock.Create("");

        protected override void ProcessRecord()
        {
            var setup = SetupMock;
            var mockBody = CreateMock;

            Collection<PSObject> preCommandOutput = null;
            if (!string.IsNullOrWhiteSpace(setup))
            {
                preCommandOutput = InvokeCommand.NewScriptBlock(setup).Invoke(FunctionName, MockWith, ParameterFilter);
            }

            var sb = InvokeCommand.NewScriptBlock(mockBody);

            var method = sb.GetType()
                .GetMethod("InvokeUsingCmdlet", BindingFlags.Instance | BindingFlags.NonPublic);

            var emptyArray = new object[0];
            var automationNull = new PSObject();
            const int writeToCurrentErrorPipe = 1;

            var input = ExpandInput(preCommandOutput);

            var @params = new object[]
                {this, false, writeToCurrentErrorPipe, automationNull, emptyArray, automationNull, new[] {input}};

            method.Invoke(sb, @params);
        }

        private static object ExpandInput(Collection<PSObject> preCommandOutput)
        {
            if (preCommandOutput == null || preCommandOutput.Count == 0)
                return null;

            if (preCommandOutput.Count == 1)
                return preCommandOutput[0];

            return preCommandOutput;
        }
    }
}
