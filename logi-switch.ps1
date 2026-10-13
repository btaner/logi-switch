<#
.SYNOPSIS
Switch a Logitech MX Keys + MX Master to the same Easy-Switch channel at once.

.EXAMPLE
.\logi-switch.ps1 2         # switch both devices to channel 2
.\logi-switch.ps1 -Status   # show which channel each device is on (no switching)

.NOTES
Talks HID++ 2.0 over Bluetooth using only built-in Windows APIs (hid.dll,
setupapi.dll): looks up the CHANGE_HOST feature (0x1814) on each device,
then calls setCurrentHost.
#>
param(
    [ValidateSet(1, 2, 3)][int]$Channel,
    [switch]$Status
)

if (-not $Status -and -not $Channel) {
    Write-Host "Usage: logi-switch.ps1 1|2|3   or   logi-switch.ps1 -Status"
    exit 1
}

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using Microsoft.Win32.SafeHandles;

public class HidDevice {
    public string Path;
    public ushort ProductId;
    public int InputLength;
    public int OutputLength;
}

public class HidConnection : IDisposable {
    FileStream stream;
    int inputLength, outputLength;
    Task<int> pendingRead;
    byte[] pendingBuffer;

    public HidConnection(HidDevice d) {
        inputLength = d.InputLength;
        outputLength = d.OutputLength;
        // GENERIC_READ|GENERIC_WRITE, FILE_SHARE_READ|WRITE, OPEN_EXISTING, FILE_FLAG_OVERLAPPED
        SafeFileHandle h = Hid.CreateFile(d.Path, 0xC0000000, 3, IntPtr.Zero, 3, 0x40000000, IntPtr.Zero);
        if (h.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error());
        stream = new FileStream(h, FileAccess.ReadWrite, 1, true);
    }

    public void Write(byte[] message) {
        byte[] buf = new byte[outputLength];
        Array.Copy(message, buf, Math.Min(message.Length, outputLength));
        stream.Write(buf, 0, buf.Length);
    }

    // Returns null on timeout.
    public byte[] Read(int timeoutMs) {
        if (pendingRead == null) {
            pendingBuffer = new byte[inputLength];
            pendingRead = stream.ReadAsync(pendingBuffer, 0, inputLength);
        }
        if (!pendingRead.Wait(timeoutMs)) return null;
        pendingRead = null;
        return pendingBuffer;
    }

    public void Dispose() { stream.Dispose(); }
}

public static class Hid {
    [StructLayout(LayoutKind.Sequential)]
    struct SP_DEVICE_INTERFACE_DATA { public int cbSize; public Guid InterfaceClassGuid; public int Flags; public IntPtr Reserved; }

    [StructLayout(LayoutKind.Sequential)]
    struct HIDD_ATTRIBUTES { public int Size; public ushort VendorID; public ushort ProductID; public ushort VersionNumber; }

    [StructLayout(LayoutKind.Sequential)]
    struct HIDP_CAPS {
        public ushort Usage, UsagePage, InputReportByteLength, OutputReportByteLength, FeatureReportByteLength;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 17)] public ushort[] Reserved;
        public ushort NumberLinkCollectionNodes, NumberInputButtonCaps, NumberInputValueCaps, NumberInputDataIndices,
            NumberOutputButtonCaps, NumberOutputValueCaps, NumberOutputDataIndices,
            NumberFeatureButtonCaps, NumberFeatureValueCaps, NumberFeatureDataIndices;
    }

    [DllImport("hid.dll")] static extern void HidD_GetHidGuid(out Guid guid);
    [DllImport("hid.dll")] static extern bool HidD_GetAttributes(SafeFileHandle h, ref HIDD_ATTRIBUTES attrs);
    [DllImport("hid.dll")] static extern bool HidD_GetPreparsedData(SafeFileHandle h, out IntPtr data);
    [DllImport("hid.dll")] static extern bool HidD_FreePreparsedData(IntPtr data);
    [DllImport("hid.dll")] static extern int HidP_GetCaps(IntPtr data, out HIDP_CAPS caps);
    [DllImport("setupapi.dll", SetLastError = true)] static extern IntPtr SetupDiGetClassDevs(ref Guid guid, IntPtr enumerator, IntPtr hwnd, int flags);
    [DllImport("setupapi.dll", SetLastError = true)] static extern bool SetupDiEnumDeviceInterfaces(IntPtr set, IntPtr info, ref Guid guid, int index, ref SP_DEVICE_INTERFACE_DATA data);
    [DllImport("setupapi.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern bool SetupDiGetDeviceInterfaceDetail(IntPtr set, ref SP_DEVICE_INTERFACE_DATA data, IntPtr detail, int size, out int required, IntPtr info);
    [DllImport("setupapi.dll")] static extern bool SetupDiDestroyDeviceInfoList(IntPtr set);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern SafeFileHandle CreateFile(string name, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);

    // All HID collections from this vendor with the given usage page.
    public static List<HidDevice> Find(ushort vendorId, ushort usagePage) {
        var found = new List<HidDevice>();
        Guid guid;
        HidD_GetHidGuid(out guid);
        IntPtr set = SetupDiGetClassDevs(ref guid, IntPtr.Zero, IntPtr.Zero, 0x12); // PRESENT | DEVICEINTERFACE
        try {
            var data = new SP_DEVICE_INTERFACE_DATA();
            data.cbSize = Marshal.SizeOf(data);
            for (int i = 0; SetupDiEnumDeviceInterfaces(set, IntPtr.Zero, ref guid, i, ref data); i++) {
                int size;
                SetupDiGetDeviceInterfaceDetail(set, ref data, IntPtr.Zero, 0, out size, IntPtr.Zero);
                IntPtr detail = Marshal.AllocHGlobal(size);
                try {
                    Marshal.WriteInt32(detail, IntPtr.Size == 8 ? 8 : 6);
                    if (!SetupDiGetDeviceInterfaceDetail(set, ref data, detail, size, out size, IntPtr.Zero)) continue;
                    string path = Marshal.PtrToStringUni(new IntPtr(detail.ToInt64() + 4));
                    HidDevice d = Inspect(path, vendorId, usagePage);
                    if (d != null) found.Add(d);
                } finally {
                    Marshal.FreeHGlobal(detail);
                }
            }
        } finally {
            SetupDiDestroyDeviceInfoList(set);
        }
        return found;
    }

    static HidDevice Inspect(string path, ushort vendorId, ushort usagePage) {
        // Access 0 = query only; works even for collections Windows holds open.
        using (SafeFileHandle h = CreateFile(path, 0, 3, IntPtr.Zero, 3, 0, IntPtr.Zero)) {
            if (h.IsInvalid) return null;
            var attrs = new HIDD_ATTRIBUTES();
            attrs.Size = Marshal.SizeOf(attrs);
            if (!HidD_GetAttributes(h, ref attrs) || attrs.VendorID != vendorId) return null;
            IntPtr pre;
            if (!HidD_GetPreparsedData(h, out pre)) return null;
            try {
                HIDP_CAPS caps;
                if (HidP_GetCaps(pre, out caps) != 0x00110000 || caps.UsagePage != usagePage) return null;
                var d = new HidDevice();
                d.Path = path;
                d.ProductId = attrs.ProductID;
                d.InputLength = caps.InputReportByteLength;
                d.OutputLength = caps.OutputReportByteLength;
                return d;
            } finally {
                HidD_FreePreparsedData(pre);
            }
        }
    }
}
'@

$Logitech = 0x046D
$HidppUsagePage = 0xFF43
$DeviceNames = @{ 0xB35B = 'MX Keys'; 0xB034 = 'MX Master 3S'; 0xB023 = 'MX Master 3' }
$LongReport = 0x11
$BleDeviceIndex = 0xFF
$SwId = 0x0A

function Send-Request($conn, [int]$featureIndex, [int]$function, [byte[]]$params = @(), [switch]$NoReply) {
    $fn = ($function -shl 4) -bor $SwId
    $conn.Write([byte[]](@($LongReport, $BleDeviceIndex, $featureIndex, $fn) + $params))
    if ($NoReply) { return }
    for ($i = 0; $i -lt 20; $i++) {
        $reply = $conn.Read(500)
        if ($null -eq $reply) { break }
        if ($reply[2] -eq 0xFF) { throw ("HID++ error 0x{0:x2}" -f $reply[5]) }
        if ($reply[2] -eq $featureIndex -and $reply[3] -eq $fn) { return , $reply[4..($reply.Length - 1)] }
    }
    throw "no reply from device"
}

function Get-ChangeHostIndex($conn) {
    $index = (Send-Request $conn 0x00 0 @(0x18, 0x14))[0]
    if ($index -eq 0) { throw "device does not support CHANGE_HOST" }
    return $index
}

$devices = [Hid]::Find($Logitech, $HidppUsagePage) | Where-Object { $DeviceNames.ContainsKey([int]$_.ProductId) }
if (-not $devices) {
    Write-Host "No MX Keys / MX Master connected to this machine."
    exit 1
}

foreach ($d in $devices) {
    $name = $DeviceNames[[int]$d.ProductId]
    $conn = $null
    try {
        $conn = New-Object HidConnection $d
        $index = Get-ChangeHostIndex $conn
        if ($Status) {
            $info = Send-Request $conn $index 0
            Write-Host ("{0}: on channel {1} of {2}" -f $name, ($info[1] + 1), $info[0])
        } else {
            Send-Request $conn $index 1 @([byte]($Channel - 1)) -NoReply
            Write-Host "${name}: switched to channel $Channel"
        }
    } catch {
        Write-Host "${name}: failed ($($_.Exception.Message))"
    } finally {
        if ($conn) { $conn.Dispose() }
    }
}
