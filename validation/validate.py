#!/usr/bin/env python3
"""Validate this handoff package, not an Anti-slop application.

Uses Python standard library; if jsonschema is available, also performs full
Draft 2020-12 metaschema/example validation. No model requests or app actions.
"""
from pathlib import Path
import hashlib,json,re,sys,zipfile
root=Path(__file__).resolve().parents[1]
checks=[]
def passed(label): checks.append(label);print('PASS',label)
required=['README.md','AGENTS.md','CLAUDE.md','CODEX_HANDOFF.md','DEVELOPMENT_HANDOFF.md','SPEC.md','UX.md','ARCHITECTURE.md','PROMPTING.md','DECISIONS.md','IMPLEMENTATION.md','ACCEPTANCE.md','SOURCES.md','prompts/primary.md','prompts/profiles/no-ai-slop.md','prompts/profiles/humanizer.md','assets/ready-editor.png','assets/processing-editor.png','assets/settings.png','third_party/PROVENANCE.md','third_party/manifest.json','validation/STATUS.md']
for name in required: assert (root/name).is_file(),name
passed('required deliverables present')
claude=(root/'CLAUDE.md').read_text()
assert re.search(r'^@AGENTS\.md$',claude,re.MULTILINE), 'missing actual AGENTS import'
assert (root/'AGENTS.md').is_file()
assert 'DEVELOPMENT_HANDOFF.md' in claude
assert len(claude.splitlines())<=4, 'shared instructions must not be duplicated'
compat=(root/'CODEX_HANDOFF.md').read_text()
assert 'Compatibility pointer' in compat and 'DEVELOPMENT_HANDOFF.md' in compat
assert len(compat.splitlines())<=4
for f in root.rglob('*.md'):
 if 'third_party' in f.relative_to(root).parts or f.name=='CODEX_HANDOFF.md':continue
 t=f.read_text()
 assert 'CODEX_HANDOFF.md' not in t,(f,'noncanonical kickoff reference')
 assert 'Codex development handoff' not in t and 'owning Codex chat' not in t,(f,'agent-specific execution branding')
passed('Claude import resolves; neutral kickoff is canonical; historical link has a short pointer')
jsons={str(f.relative_to(root)):json.loads(f.read_text()) for f in root.rglob('*.json')}
passed(f'{len(jsons)} JSON files parse')
links=0
for f in root.rglob('*.md'):
 if 'third_party' in f.relative_to(root).parts: continue # Preserve upstream files unchanged; their own repo may contain unbundled links.
 for target in re.findall(r'(?<!!)\[[^\]\n]*\]\(([^)]+)\)|!\[[^\]\n]*\]\(([^)]+)\)',f.read_text()):
  t=(target[0] or target[1]).strip().strip('<>')
  if re.match(r'[a-zA-Z][a-zA-Z0-9+.-]*:',t) or t.startswith('#'):continue
  path=t.split('#',1)[0]
  assert (f.parent/path).resolve().is_relative_to(root), (f,t,'outside package')
  assert (f.parent/path).exists(),(f,t,'missing')
  links+=1
passed(f'{links} local authored Markdown links resolve inside package')
manifest=jsons['third_party/manifest.json'];source_count=0
for repo in manifest['repositories']:
 assert re.fullmatch('[0-9a-f]{40}',repo['revision'])
 assert repo['revision']==repo['default_branch_head_at_fetch']
 assert repo['license']['github_detected_spdx_id']=='MIT'
 for item in repo['files']:
  data=(root/'third_party'/item['snapshot_path']).read_bytes()
  assert len(data)==item['size_bytes']
  assert hashlib.sha256(data).hexdigest()==item['sha256']
  assert hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()==item['git_blob_sha1']
  assert repo['revision'] in item['source_url']
  source_count+=1
 license_text=(root/'third_party'/repo['snapshot_dir']/'LICENSE').read_text()
 assert 'MIT License' in license_text and repo['license']['copyright_notice'] in license_text
passed(f'{source_count} unchanged upstream files match byte sizes, SHA256, Git blob hashes and MIT notices')
for name in ['ready-editor.png','processing-editor.png','settings.png']:
 data=(root/'assets'/name).read_bytes();assert data.startswith(b'\x89PNG\r\n\x1a\n')
passed('three image assets are PNG files')
try:
 from jsonschema import Draft202012Validator
except ImportError:
 print('NOT RUN full JSON Schema validation: install jsonschema in an isolated environment to enable it')
else:
 schemas={name:jsons[f'schemas/{name}.schema.json'] for name in ['settings','rewrite-request','rewrite-response']}
 validators={}
 for name,schema in schemas.items():
  Draft202012Validator.check_schema(schema)
  validators[name]=Draft202012Validator(schema)
  validators[name].validate(jsons[f'schemas/{name}.example.json'])
 passed('three JSON Schemas meet Draft 2020-12 metaschema; all three examples validate')
 cases=jsons['fixtures/editorial-cases.json']['cases'];assert len(cases)==18
 for c in cases:
  validators['rewrite-request'].validate(c['request'])
  validators['rewrite-response'].validate({'intent':'Fixture example','rewritten_text':c['acceptable_example'],'note':None})
  assert c['status']=='not_run'
  for protected in c['must_preserve']:assert protected in c['acceptable_example'],(c['id'],protected)
  for seg in c['request']['nearby_context'].values():
   if seg['boundary']=='unavailable':assert seg['text'] is None
   if seg['boundary']=='document_boundary':assert seg['text']==''
  assert (c['request']['style_profile_id']=='none') == (c['request']['profile_revision']=='none')
 passed('18 fixture requests and 18 illustrative responses validate; declared protected strings and boundary invariants hold')
 invalid_responses=[{'intent':'Test','rewritten_text':'X'}, {'intent':'Test','rewritten_text':'','note':None}, {'intent':'Test','rewritten_text':'X','note':None,'score':1}]
 assert all(not validators['rewrite-response'].is_valid(x) for x in invalid_responses)
 invalid_settings=dict(jsons['schemas/settings.example.json'],provider_id='unsupported-provider')
 assert not validators['settings'].is_valid(invalid_settings)
 passed('schema rejects missing note, empty replacement, extra output fields and unsupported provider')
for name in ['README.md','SPEC.md','UX.md','ARCHITECTURE.md','DEVELOPMENT_HANDOFF.md','DECISIONS.md','IMPLEMENTATION.md','ACCEPTANCE.md']:
 t=(root/name).read_text();assert 'Claude Code' in t and 'Codex' in t,name
 assert 'settings-v2.png' not in t and 'Additional Claude Code' not in t,name
passed('required provider names and canonical settings references consistent across current docs')
tone=next(c for c in jsons['fixtures/editorial-cases.json']['cases'] if c['id']=='tone_off')
assert all(x in tone['acceptable_example'] for x in ['I think','tiny','could','a lot of time'])
for name in ['UX.md','ARCHITECTURE.md','SPEC.md','ACCEPTANCE.md']:
 t=(root/name).read_text();assert 'whitespace-only' in t and ('immediately before' in t or 'rechecks' in t),name
passed('review fixes retained: tone fidelity and final empty-draft guard')
if (root/'SHA256SUMS').exists():
 for line in (root/'SHA256SUMS').read_text().splitlines():
  digest,name=line.split('  ',1);assert hashlib.sha256((root/name).read_bytes()).hexdigest()==digest,name
 passed('package SHA256SUMS verified')
if len(sys.argv)>1:
 archive=Path(sys.argv[1])
 with zipfile.ZipFile(archive) as z:
  assert z.testzip() is None
  expected={f'{root.name}/{f.relative_to(root).as_posix()}' for f in root.rglob('*') if f.is_file()}
  assert set(z.namelist())==expected,'archive inventory mismatch'
  for f in root.rglob('*'):
   if f.is_file():assert z.read(f'{root.name}/{f.relative_to(root).as_posix()}')==f.read_bytes()
 passed('ZIP integrity, exact inventory and every archived byte verified')
print(f'PACKAGE VALIDATION COMPLETE: {len(checks)} checks; no application or model tests performed')
