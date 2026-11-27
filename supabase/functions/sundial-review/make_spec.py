# Writes spec.ts from docs/SUNDIAL.md, the spec the review reads. Run from the repo root after any change to the
# spec, then deploy sundial-review again:  python3 supabase/functions/sundial-review/make_spec.py
import json
spec = open('docs/SUNDIAL.md').read()
head = ('// Generated from docs/SUNDIAL.md by make_spec.py (the spec the review reads). Do not edit here: change\n'
        '// docs/SUNDIAL.md, run  python3 supabase/functions/sundial-review/make_spec.py  and deploy sundial-review again.\n')
open('supabase/functions/sundial-review/spec.ts', 'w').write(head + 'export const SPEC = ' + json.dumps(spec) + ';\n')
print('spec.ts:', len(spec), 'characters')
