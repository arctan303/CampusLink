"""Independent stdlib oracle for the SRBX1 wire formulas (fake data only).

Protocol sources and pinned revisions: docs/providers/experimental.md.
No production module or production hash implementation is used here.
"""
import base64
import hashlib
import hmac
import json
from pathlib import Path
import random
import struct


def info(text, token):
    raw = text.encode('utf-8')
    words = list(struct.unpack('<' + 'I' * ((len(raw) + 3) // 4), raw + b'\0' * (-len(raw) % 4)))
    words.append(len(raw))
    key = struct.unpack('<4I', token.encode()[:16])
    total = 0
    right = words[-1]
    for _ in range(6 + 52 // len(words)):
        total = (total + 0x9e3779b9) & 0xffffffff
        index = total >> 2 & 3
        for pos in range(len(words)):
            left = words[(pos + 1) % len(words)]
            terms = ((right >> 5) ^ (left << 2),
                     ((left >> 3) ^ (right << 4)) ^ (total ^ left),
                     key[(pos & 3) ^ index] ^ right)
            right = words[pos] = (words[pos] + sum(terms)) & 0xffffffff
    packed = struct.pack('<' + 'I' * len(words), *words)
    table = str.maketrans('ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/',
                         'LVoJPiCN2R8G90yg+hmFHuacZ1OWMnrsSTXkYpUq/3dlbfKwv6xztjI7DeBE45QA')
    return '{SRBX1}' + base64.b64encode(packed).decode().translate(table)


rng = random.Random(20261015)
messages = ['', 'abc', 'a' * 55, 'b' * 56, 'c' * 63, 'd' * 64, 'e' * 65,
            '测试/é&=+%"\\', 'x' * 1024]
messages += [''.join(chr(rng.randrange(32, 127)) for _ in range(n)) for n in [1, 7, 80, 127, 255]]
hashes = [{'text': s, 'md5': hashlib.md5(s.encode()).hexdigest(), 'sha1': hashlib.sha1(s.encode()).hexdigest()}
          for s in messages]
hmacs = [{'key': key, 'text': text,
          'expected': hmac.new(key.encode(), text.encode(), 'md5').hexdigest()}
         for key, text in [('key', ''), ('key', 'The quick brown fox jumps over the lazy dog'),
                           ('k' * 80, '测试'), ('0123456789abcdef' * 4, 'p&=+%"\\')]]
requests = []
for mode in ['password', 'empty']:
    for username, password in [('fixture-user', 'fixture-pass'), ('u&=+%/测试', 'p"\\é&%'), ('u' * 512, 'p' * 1024)]:
        token = '0123456789abcdef' * 4
        ip, acid = '192.0.2.123', '12'
        data = dict(username=username, password=password, ip=ip, acid=acid, enc_ver='srun_bx1')
        payload = json.dumps(data, ensure_ascii=False, separators=(',', ':'))
        encoded = info(payload, token)
        digest = hmac.new(token.encode(), (password if mode == 'password' else '').encode(), 'md5').hexdigest()
        checksum = ''.join(token + item for item in [username, digest, acid, ip, '200', '1', encoded])
        requests.append({'username': username, 'password': password, 'token': token, 'ip': ip, 'ac_id': int(acid),
                         'mode': mode, 'info': encoded, 'digest': '{MD5}' + digest,
                         'chksum': hashlib.sha1(checksum.encode()).hexdigest()})
target = Path(__file__).parent / 'fixtures' / 'srun-vectors.json'
target.write_text(json.dumps(dict(hashes=hashes, hmacs=hmacs, requests=requests), ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print('Generated independent SRBX1 vectors')

# Synthetic public moduli only. No private keys or live campus data.
# Browser byte packing after reversing password+">"+mac equals big-endian bytes.
rsa = []
for bits in [1024, 2048]:
    for exponent in ['3', '10001']:
        for index in range(5):
            modulus = rng.getrandbits(bits) | (1 << (bits - 1)) | 1
            password = ['fixture-pass', 'p&=+%"\\', 'x' * (bits // 8 - 15), 'a', '~!()'][index]
            mac = 'aabbccddeeff'
            cipher = format(pow(int.from_bytes((password + '>' + mac).encode('ascii'), 'big'),
                                int(exponent, 16), modulus), 'x')
            cipher = cipher.zfill((len(cipher) + 3) // 4 * 4)
            rsa.append(dict(password=password, mac=mac, exponent=exponent,
                            modulus=format(modulus, 'x'), expected=cipher))
(target.parent / 'rsa-vectors.json').write_text(json.dumps(rsa, indent=2) + '\n', encoding='utf-8')
print('Generated independent RSA pow vectors')
