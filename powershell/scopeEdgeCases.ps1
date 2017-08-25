. "$PSScriptRoot\setup.ps1"

function i1 { 'real i1' }
function i2 { "real i2 - $(& ([scriptblock]::Create({i1})))" }

Describe 'mock function called from an unbound scriptblock' {
    New-Mock -FunctionName 'i1' -MockWith { 'fake i1' } | out-null
    It 'invokes mock' {
        $r = i2
        $r | ShouldBe 'real i2 - fake i1'
    }
}

$k = New-Module k {
    function k1 { 'real k1' }
}

$j = New-Module j {
    param($otherModule)

    function j1 { 'real j1' }
    function j2 { "real j2 - $(j1)" }
    function j3 { "real j3 - $(k1)" }

    $x = New-Module x {
        function x1 { "real x1 - $(j1)" }
    }

    function j4 {
        "real j4 - $(& ([scriptblock]::Create({j1})))"
    }
    function j5 {
        "real j5 - $(& ([scriptblock]::Create({k1})))"
    }
    function j6 {
        & $otherModule.NewBoundScriptBlock({
            "real j6 - $(k1)"
        })
    }
} -ArgumentList $k

Describe 'mock function inside a module' {
    New-Mock -FunctionName 'j1' -MockWith { 'fake j1' } | out-null
    It 'invokes mock' {
        $r = j1
        $r | ShouldBe 'fake j1'
    }
}

Describe 'mock function inside a module called inside that module' {
    New-Mock -FunctionName 'j1' -MockWith { 'fake j1' } | out-null
    It 'invokes mock' {
        $r = j2
        $r | ShouldBe 'real j2 - fake j1'
    }
}

Describe 'mock function inside a module called from another module' {
    New-Mock -FunctionName 'k1' -MockWith { 'fake k1' } | out-null
    It 'invokes mock' {
        $r = j3
        $r | ShouldBe 'real j3 - fake k1'
    }    
}

Describe 'mock function inside one module called from another module inside that module' {
    New-Mock -FunctionName 'j1' -MockWith { 'fake j1' } | out-null
    It 'invokes mock' {
        $r = x1
        $r | ShouldBe 'real x1 - fake j1'
    }    
}

Describe 'mock function inside a module invoked from an unbound scriptblock' {
    New-Mock -FunctionName 'j1' -MockWith { 'fake j1' } | Out-Null
    It 'invokes mock' {
        $r = j4
        $r | ShouldBe 'real j4 - fake j1'
    }
}

Describe 'mock function inside a module invoked from an unbound scriptblock from another module' {
    New-Mock -FunctionName 'k1' -MockWith { 'fake k1' } | out-null
    It 'invokes mocks' {
        $r = j5
        $r | ShouldBe 'real j5 - fake k1'
    }
}

Describe 'mock function invoked from a scriptblock late bound to another module' {
    New-Mock -FunctionName 'k2' -MockWith { 'fake k2' } | out-null
    It 'invokes mocks' {
        $r = j6
        $r | ShouldBe 'real j6 - fake k2'
    }
}