import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";

const sshString = (buf) => {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(buf.length);
  return Buffer.concat([len, buf]);
};

function keyFromSeed(label) {
  const seed = crypto.createHash("sha256").update(label).digest();
  const pkcs8 = Buffer.concat([Buffer.from("302e020100300506032b657004220420", "hex"), seed]);
  const priv = crypto.createPrivateKey({ key: pkcs8, format: "der", type: "pkcs8" });
  const pub = crypto.createPublicKey(priv).export({ format: "der", type: "spki" }).subarray(-32);
  return { seed, pub };
}

function opensshFiles({ seed, pub }, comment) {
  const type = Buffer.from("ssh-ed25519");
  const pubBlob = Buffer.concat([sshString(type), sshString(pub)]);
  const check = Buffer.from("VRAI");
  let priv = Buffer.concat([check, check, sshString(type), sshString(pub), sshString(Buffer.concat([seed, pub])), sshString(Buffer.from(comment))]);
  for (let i = 1; priv.length % 8 !== 0; i++) priv = Buffer.concat([priv, Buffer.from([i])]);
  const body = Buffer.concat([
    Buffer.from("openssh-key-v1\0"),
    sshString(Buffer.from("none")),
    sshString(Buffer.from("none")),
    sshString(Buffer.alloc(0)),
    Buffer.from([0, 0, 0, 1]),
    sshString(pubBlob),
    sshString(priv)
  ]);
  const wrapped = body.toString("base64").match(/.{1,70}/g).join("\n");
  return {
    private: "-----BEGIN OPENSSH PRIVATE KEY-----\n" + wrapped + "\n-----END OPENSSH PRIVATE KEY-----\n",
    public: "ssh-ed25519 " + pubBlob.toString("base64") + " " + comment + "\n",
    publicKey: "ssh-ed25519 " + pubBlob.toString("base64")
  };
}

export function writeKeys(sshDir, people) {
  fs.mkdirSync(path.join(sshDir, "people"), { recursive: true, mode: 0o700 });
  const write = (file, files) => {
    fs.writeFileSync(file, files.private, { mode: 0o600 });
    fs.writeFileSync(file + ".pub", files.public, { mode: 0o644 });
    return file;
  };
  const byName = {};
  const signers = [];
  for (const [name, email] of Object.entries(people)) {
    const files = opensshFiles(keyFromSeed("vrai fixture key for " + email), email);
    const slug = email.split("@")[0];
    byName[name] = write(slug === "avery" ? path.join(sshDir, "id_ed25519") : path.join(sshDir, "people", slug + "_ed25519"), files);
    signers.push(email + " " + files.publicKey);
  }
  const stranger = write(path.join(sshDir, "people", "stranger_ed25519"), opensshFiles(keyFromSeed("vrai fixture stranger key"), "stranger@example.com"));
  const allowedSigners = path.join(sshDir, "allowed_signers");
  fs.writeFileSync(allowedSigners, signers.join("\n") + "\n");
  return { team: byName["Avery Chen"], byName, stranger, allowedSigners };
}
