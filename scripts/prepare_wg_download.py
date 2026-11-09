"""Stage public WG core downloads; never includes VPN profiles or private keys."""
from pathlib import Path
import hashlib,json,shutil,os,tarfile
root=Path(__file__).resolve().parents[1]
out=root/'dist'/'wg'
files={}
for abi in ['arm64-v8a','armeabi-v7a','x86_64']:
    dst=out/abi/'libawg.so'
    dst.parent.mkdir(parents=True,exist_ok=True)
    if not dst.is_file(): raise FileNotFoundError(f"Build WG first: {dst}")
    files[abi]={'file':f'{abi}/libawg.so','size':dst.stat().st_size,'sha256':hashlib.file_digest(dst.open('rb'),'sha256').hexdigest()}
src=root/'linux/core/amnezia-box'
if src.exists():
    dst=out/'amd64'/'amnezia-box';dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,dst)
    files['amd64']={'file':'amd64/amnezia-box','size':dst.stat().st_size,'sha256':hashlib.file_digest(dst.open('rb'),'sha256').hexdigest()}
(out/'manifest.json').write_text(json.dumps({'version':'1.260910.0-nextlink-linker1','files':files},indent=2)+'\n')
print(f'Staged WG cores: {out}')

shutil.copy2(root/'third_party/amnezia-box/LICENSE',out/'LICENSE')
shutil.copy2(root/'third_party/amnezia-box/README.md',out/'SOURCE.md')
source=Path(os.environ.get('NEXTLINK_AWG_SOURCE_DIR','/tmp/nextlink-amnezia-download-source'))
if (source/'go.mod').exists():
    with tarfile.open(out/'amnezia-box-source.tar.gz','w:gz') as archive:
        for file in source.rglob('*'):
            if '.git' not in file.parts and file.is_file():
                archive.add(file,arcname=str(Path('amnezia-box')/file.relative_to(source)),recursive=False)
shutil.copy2(root/'scripts/build_amnezia_core.sh',out/'build_amnezia_core.sh')
