# Mock
Prototyping better Mock for Pester.

> This is still early in developement, but your opinions are very welcome.

- Use function shadowing as the mocking mechanism. This allows PowerShell to manage mocks automatically and consistently. This also gives us extremely simple way of explaining mocks. They are simple re-definition of the function. Done. ✓

```PowerShell
New-Mock -FunctionName 'i1' -MockWith { 'fake i1' }

# is the same as
function i1 () {
    # a bit of mock counting code
    #...

    # your body
    'fake i1'
}
```

- Be able to mock function in module scope (or multiple module scopes), and then transition back to the script scope to test the public surface of your module. Done. ✓

```powershell
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
```

See [this example](powershell/readme-example-scoping-simple.ps1) and [annontated version that validates the scopes](powershell/readme-example-scoping-annotated.ps1) in code.

- Detach Mock from Pester, and only make it rely on common Stack mechanism, to allow mock call counting. Partially done.

- Make mock resolve easier to understand, filtering mocks based on ParameterFilter is extremely hard to debug now, I want to see what mocks are available, which were candidates for call, and why they were rejected. Not done.

- Make it possible to relax mock parameters to avoid re-validating parameters, or to avoid parameters with types that we cannot create. Not done.

- Make mock output it's configuration so I can reuse the object for asserting, possibly give mock a name to do the same. Not done.