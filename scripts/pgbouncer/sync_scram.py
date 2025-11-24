#!/usr/bin/env python3
import argparse, os, tempfile
import psycopg2

def fetch_scram_secret(db_url: str, username: str) -> str:
    """Return the SCRAM-SHA-256 verifier for `username` from CockroachDB."""
    with psycopg2.connect(db_url) as conn:
        with conn.cursor() as cur:
            # Get readable SCRAM string instead of \x... hex bytes
            cur.execute("SET bytea_output = 'escape'")
            cur.execute('SELECT "hashedPassword" FROM system.users WHERE username = %s', (username,))
            row = cur.fetchone()
            if not row or row[0] is None:
                raise SystemExit(f"User not found or no hashedPassword: {username}")

            val = row[0]
            # psycopg2 returns bytea as memoryview/bytes; normalize to str
            if isinstance(val, memoryview):  # psycopg2 often returns memoryview
                val = bytes(val)
            if isinstance(val, (bytes, bytearray)):
                # Could be b'\\x...' (hex) or already the SCRAM string bytes
                if val.startswith(b'\\x'):
                    scram = bytes.fromhex(val[2:].decode('ascii')).decode('ascii')
                else:
                    scram = val.decode('ascii', 'strict')
            else:
                s = str(val)
                scram = bytes.fromhex(s[2:]).decode('ascii') if s.startswith('\\x') else s

            if not scram.startswith("SCRAM-SHA-256$"):
                raise SystemExit("Fetched value is not a SCRAM-SHA-256 verifier.")
            return scram

def update_userlist(userlist_path: str, username: str, scram: str) -> None:
    """Replace or append the user’s entry in userlist.txt safely."""
    quoted = f"\"{username}\" \"{scram}\""
    lines = []
    found = False

    if os.path.exists(userlist_path):
        with open(userlist_path, "r", encoding="utf-8") as f:
            for line in f:
                if line.lstrip().startswith(f"\"{username}\" "):
                    lines.append(quoted + "\n")
                    found = True
                else:
                    lines.append(line)
    if not found:
        lines.append(quoted + "\n")

    # Atomic write with 0600 perms
    dname = os.path.dirname(os.path.abspath(userlist_path)) or "."
    with tempfile.NamedTemporaryFile("w", dir=dname, delete=False, encoding="utf-8") as tmp:
        tmp.write("".join(lines))
        tmp_name = tmp.name
    os.chmod(tmp_name, 0o600)
    os.replace(tmp_name, userlist_path)

def main():
    ap = argparse.ArgumentParser(description="Sync SCRAM secret from CockroachDB into PgBouncer userlist.txt")
    ap.add_argument("--username", required=True, help="SQL username to fetch")
    ap.add_argument("--password", required=True, help="CockroachDB credentials for user")
    ap.add_argument("--hostname", required=True, help="CockroachDB proxy host for connections")
    ap.add_argument("--port", required=True, help="CockroachDB port for connections")
    ap.add_argument("--database", required=True, help="CockroachDB database for connections")
    ap.add_argument("--root_crt", required=True, help="CockroachDB root cert used for connections")
    ap.add_argument("--userlist", required=True, help="Path to PgBouncer userlist.txt")
    args = ap.parse_args()

    url = f"postgresql://{args.username}:{args.password}@{args.hostname}:{args.port}/{args.database}?sslmode=verify-full&sslrootcert={args.root_crt}"
    scram = fetch_scram_secret(url, args.username)
    update_userlist(args.userlist, args.username, scram)
    print(f"Updated {args.userlist} with SCRAM for user {args.username}")

if __name__ == "__main__":
    main()
