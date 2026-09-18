(function () {
    const consent = document.getElementById("consent");
    const note = document.getElementById("note");
    const generate = document.getElementById("generate");
    const status = document.getElementById("status");

    function setStatus(msg, isError) {
        status.textContent = msg || "";
        status.classList.toggle("error", !!isError);
    }

    function syncButton() {
        generate.disabled = !consent.checked || generate.dataset.busy === "1";
    }

    consent.addEventListener("change", syncButton);
    syncButton();

    function downloadBytes(filename, bytes) {
        const blob = new Blob([bytes], { type: "application/gzip" });
        const url = URL.createObjectURL(blob);
        const a = document.createElement("a");
        a.href = url;
        a.download = filename;
        document.body.appendChild(a);
        a.click();
        a.remove();
        URL.revokeObjectURL(url);
    }

    function b64ToBytes(b64) {
        const bin = atob(String(b64).replace(/\s+/g, ""));
        const bytes = new Uint8Array(bin.length);
        for (let i = 0; i < bin.length; i++)
            bytes[i] = bin.charCodeAt(i);
        return bytes;
    }

    // UTF-8 → base64 for --note-b64 (Cockpit spawn does not reliably close stdin).
    function utf8ToB64(text) {
        const bytes = new TextEncoder().encode(text);
        let bin = "";
        for (let i = 0; i < bytes.length; i++)
            bin += String.fromCharCode(bytes[i]);
        return btoa(bin);
    }

    generate.addEventListener("click", function () {
        if (!consent.checked || generate.dataset.busy === "1")
            return;

        generate.dataset.busy = "1";
        syncButton();
        setStatus("Collecting and redacting logs… this can take a minute.");

        const noteText = note.value || "";
        const args = ["/usr/lib/pistomp/collect-debug-bundle"];
        if (noteText)
            args.push("--note-b64", utf8ToB64(noteText));

        cockpit.spawn(args, {
            err: "message",
            superuser: "try",
        })
            .then(function (path) {
                const outPath = String(path).trim();
                if (!outPath) {
                    throw new Error("Collector returned no output path");
                }
                setStatus("Preparing download…");
                const filename = outPath.split("/").pop() || "pistomp-support.tar.gz";
                // base64 through the text channel — cockpit.spawn binary mode
                // still UTF-8-decodes on some versions and blows up on gzip (0x1f 0x8b).
                return cockpit.spawn(["base64", "-w", "0", outPath], {
                    err: "message",
                    superuser: "try",
                }).then(function (b64) {
                    downloadBytes(filename, b64ToBytes(b64));
                    setStatus("Download started: " + filename);
                    return cockpit.spawn(["rm", "-f", outPath], {
                        err: "ignore",
                        superuser: "try",
                    });
                });
            })
            .catch(function (ex) {
                const msg = (ex && (ex.message || ex.problem)) || String(ex);
                setStatus("Failed: " + msg, true);
            })
            .finally(function () {
                generate.dataset.busy = "0";
                syncButton();
            });
    });
}());
