. $PSScriptRoot\setup.ps1
# define a module l that exports function l1, but does not export function l2
# we want to mock the hidden function l2, but still test l1 from the outside of the
# module
Get-Module l | Remove-Module -Force
New-Module -Name l {
    function l1 { l2 }
    function l2 { "l2 function" }

    Export-ModuleMember -Function l1
} | Import-Module -Force

Save-ScriptScope
Describe 'mock function inside a module and then call it from outside' {
    Invoke-InModuleScope -ModuleName l -ScriptBlock {
        New-Mock -FunctionName 'l2' -MockWith { 'mocked l2' } | out-null
        Invoke-InScriptScope {
            It 'function l1 calls the mocked version of l2' {
                l1 | ShouldBe 'mocked l2'
            }
        }
    }
}