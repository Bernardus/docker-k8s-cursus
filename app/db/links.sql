-- Tabel en voorbeelddata voor de snip-database.
-- Mag je meerdere keren uitvoeren: bestaande rijen worden overgeslagen.

CREATE TABLE IF NOT EXISTS links (
  code       text PRIMARY KEY,
  url        text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO links (code, url) VALUES
  ('gh',     'https://github.com'),
  ('k8s',    'https://kubernetes.io'),
  ('podman', 'https://podman.io')
ON CONFLICT (code) DO NOTHING;

SELECT * FROM links;
