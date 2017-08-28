. $PSScriptRoot\setup.ps1
# define a module l that exports function l1, but does not export function l2
# we want to mock the hidden function l2, but still test l1 from the outside of the
# module
Get-Module l | Remove-Module -Force
New-Module -Name l {
    $scope = "module"
    function l1 { l2 }
    function l2 { "l2 function" }

    Export-ModuleMember -Function l1
} | Import-Module -Force


# we need to run inside of the module scope to mock l2
# but we move back to our script scope when we run l1
# to keep testing the public surface of the module
# and to have variables from the correct scope

# pin the scriptscope (this can be automatic to some extent)
Save-ScriptScope

# define scope variable so we can assert in which
# scope we are
$scope = 'script'

Describe 'mock function inside a module and then call it from outside' {
    # let's check we start from the script scope
    It 'we are in script scope' {
        $scope | ShouldBe 'script'
    }

    It 'we cannot see function l2 because it is not exported' {
        (Get-Command -Name 'l2' -ModuleName l -ErrorAction SilentlyContinue).Count | ShouldBe 0
    }

    It 'we can run function l1 because it is exported' {
        l1
    }

    # move to the scope of the l module so we can reach it's
    # internal functions and variables
    Invoke-InModuleScope -ModuleName l -ScriptBlock {
        # let's validate that we are in fact inside of module l
        It 'out `$scope variable is set to value module' {
            $scope | ShouldBe 'module'
        }

        It 'we can run function l2 because we are inside of the module' {
            l2
        }

        # define the mock to shadow function l2
        New-Mock -FunctionName 'l2' -MockWith { 'mocked l2' } | out-null

        # now we are done with our setup so let's move back to the script
        # scope (the one we pinned) and validate that we are in fact there
        Invoke-InScriptScope {
            It 'we are in script scope' {
                $scope | ShouldBe 'script'
            }

            It 'we cannot see function l2 because it is not exported' {
                (Get-Command -Name 'l2' -ModuleName l -ErrorAction SilentlyContinue).Count | ShouldBe 0
            }

            It 'we can run function l1 because it is exported' {
                l1
            }

            It 'function l1 calls the mocked version of l2' {
                l1 | ShouldBe 'mocked l2'
            }
        }
        # here we are in module scope again, and the mock of l2 is still in place
    }
    # here we are in script scope again, and the mock of l2 is gone
    # because the scriptblock in which it was defined has ended
}