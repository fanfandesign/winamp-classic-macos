"""Package the original Winamp logo into a multi-resolution macOS ICNS."""
import pathlib, struct, subprocess
root = pathlib.Path(__file__).resolve().parent
project = root.parent
binary = project / 'build/make-classic-icon'
binary.parent.mkdir(exist_ok=True)
subprocess.run(['swiftc','-module-cache-path',str(project/'build/ModuleCache'),str(project/'Tools/MakeClassicIcon.swift'),'-o',str(binary)],check=True,cwd=project)
subprocess.run([str(binary)],check=True,cwd=project)
entries = [(b'icp4',16),(b'icp5',32),(b'icp6',64),(b'ic07',128),(b'ic08',256),(b'ic09',512),(b'ic10',1024)]
body = bytearray()
for kind,size in entries:
    png=(root/'WinampClassic.iconset'/f'size-{size}.png').read_bytes()
    body.extend(kind+struct.pack('>I',len(png)+8)+png)
(root/'WinampOriginal.icns').write_bytes(b'icns'+struct.pack('>I',len(body)+8)+body)
