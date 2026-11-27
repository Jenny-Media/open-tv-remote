# Just a TV Remote privacy policy

_Last updated: November 27, 2026_

Just a TV Remote is an independent fork of Open TV Remote. Jenny Media LLC does not operate an app server and does not collect analytics, advertising identifiers or tracking data. No developer account is required in the app.

- **Local network:** discovery and TV commands go directly from your device to devices on your network. Local Network permission is used to find and control TVs. Discovery runs in the device chooser, which opens automatically on first launch, and when recovering a saved TV whose network address changed. You can deny Local Network access. Pairing and TV control actions are user initiated.
- **Local storage:** the app saves TV names, brands, network and MAC addresses when available, model information, interface preferences, and any Jellyfin server and pinned items you configure. Samsung and LG pairing tokens are saved in the app’s local storage. Android TV client keys and certificates are stored in this device’s keychain. TV pairing credentials are excluded from the app’s iCloud settings sync.
- **iCloud:** if iCloud key-value storage is available, saved TV details (name, brand, network and MAC addresses, and model), visible-app preferences, and Jellyfin settings and pins (including server address and user name and ID) can sync through your Apple iCloud account to your devices running Just a TV Remote. Just a TV Remote uses separate iCloud storage from Open Remote Test and the original app. Synced settings are processed by Apple under your iCloud settings and Apple’s privacy policy. Deleting the app does not necessarily delete keychain entries or settings already stored in iCloud.
- **Jellyfin:** optional Jellyfin requests go to the server you choose. That server may be outside your home network, depending on its address and configuration. Its operator controls its own logs and privacy practices. Jellyfin authentication tokens are saved in the keychain with iCloud Keychain synchronization enabled, subject to your Apple account and device settings.
- **Live Activities:** the selected TV’s name and brand can appear on your Lock Screen and Dynamic Island. You can stop the remote session or turn off automatic display in the app’s Settings. Activity links contain an opaque session identifier, not a TV address or pairing token.
- **TestFlight:** If you install a beta build through TestFlight, Apple processes installation, crash and feedback information through that service. If you submit feedback, Apple may share it with the developer. Apple’s privacy policy and TestFlight terms govern that service.

For privacy questions, email [remote@jenny.media](mailto:remote@jenny.media).

Source and support: [Jenny-Media/open-tv-remote](https://github.com/Jenny-Media/open-tv-remote). Original project: [iamnbutler/open-tv-remote](https://github.com/iamnbutler/open-tv-remote). Open-source and asset notices are preserved in the app and repository.
