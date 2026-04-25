import json
import os

with open('../Sources/SwiftOBD2/Resources/codes.json', 'r', encoding='utf-8') as f:
    data = json.load(f)

with open('lib/src/data/trouble_codes.dart', 'w', encoding='utf-8') as f:
    f.write("import '../decoders.dart';\n\n")
    f.write("final Map<String, TroubleCodeMetadata> troubleCodeDictionary = {\n")
    causes = data['causes']
    remedies = data['remedies']
    codes = data['codes']
    
    for code, info in codes.items():
        title = info['title'].replace('"', '\\"')
        desc = info['description'].replace('"', '\\"')
        
        c_list = [causes[i].replace('"', '\\"') for i in info.get('causeIndexes', [])]
        r_list = [remedies[i].replace('"', '\\"') for i in info.get('remedyIndexes', [])]
        
        c_str = ', '.join(f'"{c}"' for c in c_list)
        r_str = ', '.join(f'"{r}"' for r in r_list)
        
        f.write(f'  "{code}": TroubleCodeMetadata(code: "{code}", title: "{title}", description: "{desc}", severity: "Moderate", causes: [{c_str}], remedies: [{r_str}]),\n')

    f.write("};\n")
