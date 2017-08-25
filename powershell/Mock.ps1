. "$PSScriptRoot\setup.ps1"

# Here finally the real stuff happens. the mock should run out of scope
# automatically without any intervention from the test framework
function a () { "I am real - $existingValue"}

$existingValue = 'value from outside'
a # <- real function real value
Describe "describe " {
    a # <- real function, real value
    New-Mock -FunctionName "a" -MockWith { "mock from describe - '$existingValue'" } | out-null
    a # <- mock from describe real value
    $existingValue = "value from describe"
    a # <- mock from describe value from describe
    
    Context "context" { 
        a # <- mock from describe value from describe
        New-Mock -FunctionName "a" -MockWith { "mock from context - '$existingValue'" } | out-null
        a # <- mock from context value from describe
        $existingValue = "value from context"
        a # <- mock from context value from context
        
        It "it" {
            a # <- mock from context value from context
            New-Mock -FunctionName "a" -MockWith { "mock from it - '$existingValue'" } | out-null
            a # <- mock from it value from context
            $existingValue = "value from it"
            a # <- mock from it value from it
        }
        a # <- mock from context value from context
    }
    a # <- mock from describe value from describe
}
# real function, real value
a


Get-MockCallHistory | 
    select MockId, FunctionName, @{n="ScopeHistory"; e={ $_ | select -ExpandProperty scope | select -expand name }} | 
    Out-String
    
Get-MockTable | Out-String