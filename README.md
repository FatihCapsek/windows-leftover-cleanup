# windows-leftover-cleanup

A [Claude](https://claude.ai) skill that cleans up a Windows PC safely. You choose what to scan:

| Scan | Finds |
|---|---|
| **Leftovers** | folders and settings left by uninstalled apps, caches, empty folders, dead startup entries and shortcuts |
| **Apps** | installed programs, Store apps and games you probably don't need (Visual Studio leftovers, old .NET patches, telemetry tools, launchers without games…) |
| **Files** | the largest files on every drive, old installers in Downloads, duplicate files, Windows update clutter |

**[Türkçe açıklama aşağıda ↓](#türkçe)**

## What it does

1. **Scans** (read-only) what you picked. The leftover scan compares folders in `AppData` (Local, Roaming, LocalLow), `ProgramData` and `Program Files` with the list of installed programs, Store apps, running processes and services. It also finds caches, empty folders, startup entries that point to deleted programs, and broken shortcuts.
2. **Shows you the list** in three groups, with sizes: safe leftovers, caches, and items you need to decide on. Nothing is removed yet.
3. **Removes only what you approve.** Programs are uninstalled with their own uninstallers (MSI, Squirrel/Electron and others), so drivers and services go too. Leftover folders are **sent to the Recycle Bin**, never permanently deleted. Folders that need admin rights get a single UAC prompt.
4. **Reports** what was removed, how much space was freed, and what was skipped and why.

### Safety

- Nothing is deleted without your approval. Everything goes to the Recycle Bin, so you can restore it. The skill never empties the Recycle Bin.
- It looks inside folders before suggesting them. Game saves, call recordings, Minecraft worlds and other personal data are flagged and left alone unless you choose them.
- Windows folders, shared runtimes (.NET, VC++), Docker/WSL data and the data of installed apps are never touched.
- Works on Turkish Windows too. It handles the Turkish `I/ı` casing problem, which otherwise turns `MSI` into `ms`.

## Install

**Claude Code** (CLI / desktop app):

```
/plugin marketplace add FatihCapsek/windows-leftover-cleanup
/plugin install windows-leftover-cleanup@fatihcapsek-skills
```

**Claude app (claude.ai / desktop):** download `windows-leftover-cleanup.skill` from [Releases](https://github.com/FatihCapsek/windows-leftover-cleanup/releases), then upload it under **Settings → Capabilities → Skills**.

## Use

Just ask, in any language. For example:

- "Find the junk my old programs left behind and show it to me."
- "Uninstall FACEIT completely."
- "My C: drive is almost full, clean it up."
- "Do I have apps I don't need?"
- "What are the biggest files on my PC?"

## Requirements

- Windows 10/11 with Windows PowerShell 5.1 (built in)
- Claude with the ability to run PowerShell commands (Claude Code, or the desktop app's Code tab)

## Files

```
skills/windows-leftover-cleanup/
├── SKILL.md                    # instructions for Claude
├── references/
│   ├── apps.md                 # how to judge installed apps
│   └── files.md                # how to judge large files
└── scripts/
    ├── scan_leftovers.ps1      # read-only: leftovers of uninstalled apps
    ├── scan_apps.ps1           # read-only: installed apps, games, startup
    ├── scan_files.ps1          # read-only: large / duplicate / old files
    └── recycle.ps1             # sends approved paths to the Recycle Bin
```

You can also run the scanner on its own:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File skills\windows-leftover-cleanup\scripts\scan_leftovers.ps1
```

## License

[MIT](LICENSE)

---

## Türkçe

Windows bilgisayarını güvenle temizleyen bir [Claude](https://claude.ai) skill'i. Neyin taranacağını sen seçersin:

| Tarama | Ne bulur |
|---|---|
| **Kalıntılar** | Kaldırılmış programlardan kalan klasörler, önbellekler, boş klasörler, bozuk açılış kayıtları ve kısayollar |
| **Uygulamalar** | Muhtemelen ihtiyacın olmayan programlar, Store uygulamaları ve oyunlar (Visual Studio artıkları, eski .NET yamaları, veri toplayan araçlar, oyunsuz başlatıcılar…) |
| **Dosyalar** | Tüm disklerdeki en büyük dosyalar, İndirilenler'deki eski kurulum dosyaları, kopya dosyalar, Windows güncelleme artıkları |

### Ne yapar?

1. **Seçtiğin taramayı yapar** (hiçbir şey silmez). Kalıntı taraması `AppData` (Local, Roaming, LocalLow), `ProgramData` ve `Program Files` klasörlerini yüklü programlar, Store uygulamaları, çalışan işlemler ve servislerle karşılaştırır. Önbellekleri, boş klasörleri, silinmiş programları açılışta başlatmaya çalışan kayıtları ve bozuk kısayolları da bulur.
2. **Listeyi gösterir.** Bulduklarını boyutlarıyla birlikte üç grupta sunar: güvenli kalıntılar, önbellek ve senin karar vermen gerekenler. Bu aşamada hiçbir şey silinmez.
3. **Sadece onayladıklarını kaldırır.** Programları kendi kaldırma araçlarıyla kaldırır (MSI, Squirrel/Electron ve diğerleri), böylece sürücüleri ve servisleri de gider. Kalan klasörleri **Geri Dönüşüm Kutusu'na** gönderir, asla kalıcı olarak silmez. Yönetici izni gereken klasörler için tek bir onay penceresi açar.
4. **Rapor verir:** Neyin silindiğini, ne kadar yer açıldığını, neyin atlandığını ve nedenini anlatır.

### Güvenlik

- Onayın olmadan hiçbir şey silinmez. Her şey Geri Dönüşüm Kutusu'na gider, istersen geri alabilirsin. Skill, Geri Dönüşüm Kutusu'nu asla kendisi boşaltmaz.
- Bir klasörü önermeden önce içine bakar. Oyun kayıtları, arama kayıtları, Minecraft dünyaları gibi kişisel verileri işaretler ve sen seçmedikçe dokunmaz.
- Windows klasörlerine, ortak bileşenlere (.NET, VC++), Docker/WSL verilerine ve yüklü programların verilerine dokunmaz.
- Türkçe Windows'ta da doğru çalışır. Aksi halde `MSI` adını `ms`ye çeviren `I/ı` sorununu çözer.

### Kurulum

**Claude Code:**

```
/plugin marketplace add FatihCapsek/windows-leftover-cleanup
/plugin install windows-leftover-cleanup@fatihcapsek-skills
```

**Claude uygulaması:** [Releases](https://github.com/FatihCapsek/windows-leftover-cleanup/releases) sayfasından `windows-leftover-cleanup.skill` dosyasını indir, sonra **Ayarlar → Capabilities → Skills** bölümünden yükle.

### Kullanım

Claude'a normal bir şekilde yazman yeterli. Örneğin:

- "Eski programlardan kalan gereksiz dosyaları bul ve bana göster."
- "FACEIT'i tamamen kaldır."
- "C: diskim doldu, temizle."
- "PC'de gereksiz uygulama var mı?"
- "En büyük dosyalarım neler?"
