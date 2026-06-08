Sub init()
    ' UI nodes
    m.backdrop      = m.top.findNode("backdrop")
    m.topArt        = m.top.findNode("topArt")
    m.topTitle      = m.top.findNode("topTitle")
    m.topSubtitle   = m.top.findNode("topSubtitle")
    m.topDesc       = m.top.findNode("topDesc")
    m.progressBg    = m.top.findNode("progressBg")
    m.progressFill  = m.top.findNode("progressFill")
    m.timeLabel     = m.top.findNode("timeLabel")
    m.controlsHint  = m.top.findNode("controlsHint")
    m.tileGrid      = m.top.findNode("tileGrid")
    m.gridStatus    = m.top.findNode("gridStatus")
    m.keyHints      = m.top.findNode("keyHints")
    m.tabs          = [m.top.findNode("tab0"), m.top.findNode("tab1"), m.top.findNode("tab2"), m.top.findNode("tab3")]
    m.tabLines      = [m.top.findNode("tab0line"), m.top.findNode("tab1line"), m.top.findNode("tab2line"), m.top.findNode("tab3line")]

    ' Map m.status -> gridStatus so legacy status calls still work
    m.status = m.gridStatus

    m.backdropFade   = m.top.findNode("backdropFade")
    m.podcastDetail  = m.top.findNode("podcastDetail")
    m.detailArt      = m.top.findNode("detailArt")
    m.detailDate     = m.top.findNode("detailDate")
    m.detailTitle    = m.top.findNode("detailTitle")
    m.detailPodcast  = m.top.findNode("detailPodcast")
    m.detailTime     = m.top.findNode("detailTime")
    m.detailDesc     = m.top.findNode("detailDesc")

    m.focusTimer = CreateObject("roSGNode", "Timer")
    m.focusTimer.duration = 0.15
    m.focusTimer.repeat = false
    m.focusTimer.observeField("fire", "onFocusTimer")

    m.tileGrid.observeField("itemFocused",  "onTileFocused")
    m.tileGrid.observeField("itemSelected", "onTileSelected")

    m.nowPlaying = m.top.findNode("nowPlaying")

    m.mode             = "boot"
    m.navIndex         = 0
    m.gridIdx          = 0
    m.nowPlayingActive = false
    m.isCurrentlyLive  = false
    m.pendingBackdropUrl = ""
    m.numColumns = 6
    m.top.setFocus(true)

    ' Device ID
    devReg = CreateObject("roRegistrySection", "device")
    m.deviceId = devReg.Read("pc_device_id")
    if m.deviceId = invalid or m.deviceId = ""
        m.deviceId = CreateObject("roDeviceInfo").GetChannelClientId()
        devReg.Write("pc_device_id", m.deviceId)
        devReg.Flush()
    end if

    auth = AuthRead()
    if auth <> invalid and auth.token <> ""
        showMain(auth)
    else
        promptEmail()
    end if
End Sub

' ---- login flow -------------------------------------------------------------

Sub promptEmail()
    m.mode = "login_email"
    m.expectingEmailButton = true
    dlg = CreateObject("roSGNode", "KeyboardDialog")
    dlg.title = "Pocket Casts Email"
    dlg.text = TestEmail()
    dlg.buttons = ["Next", "Cancel"]
    m.dlg = dlg
    dlg.observeField("buttonSelected", "onEmailBtn")
    m.top.dialog = dlg
End Sub

Sub onEmailBtn()
    if not m.expectingEmailButton then return
    m.expectingEmailButton = false
    if m.dlg.buttonSelected = 0
        m.email = m.dlg.text
        closeDialog()
        promptPassword()
    else
        closeDialog()
        promptEmail()
    end if
End Sub

Sub promptPassword()
    m.mode = "login_password"
    m.expectingPasswordButton = true
    dlg = CreateObject("roSGNode", "KeyboardDialog")
    dlg.title = "Pocket Casts Password"
    dlg.text = TestPassword()
    dlg.buttons = ["Log In", "Back"]
    m.dlg = dlg
    dlg.observeField("buttonSelected", "onPasswordBtn")
    m.top.dialog = dlg
End Sub

Sub onPasswordBtn()
    if not m.expectingPasswordButton then return
    m.expectingPasswordButton = false
    if m.dlg.buttonSelected = 0
        m.password = m.dlg.text
        closeDialog()
        doLogin()
    else
        closeDialog()
        promptEmail()
    end if
End Sub

Sub closeDialog()
    if m.dlg <> invalid then m.dlg.close = true
    m.top.dialog = invalid
    m.dlg = invalid
End Sub

Sub doLogin()
    setStatus("Logging in...")
    m.relay = CreateObject("roSGNode", "RelayTask")
    m.relay.observeField("response", "onLoginResp")
    m.relay.bodyJson = FormatJSON({ action: "login", email: m.email, password: m.password })
    m.relay.control = "RUN"
End Sub

Sub onLoginResp()
    code = m.relay.status
    if code = 401 or code = 403
        AuthClear()
        setStatus("Invalid credentials. Try again.")
        promptPassword()
        return
    end if
    if code <> 200
        setStatus("Login failed (" + code.ToStr() + "). Check network.")
        promptEmail()
        return
    end if
    data = ParseJSON(m.relay.response)
    if data = invalid or data.token = invalid or data.token = ""
        setStatus("Login failed (bad response). Try again.")
        promptEmail()
        return
    end if
    AuthWrite(data.token, data.userId, data.email)
    showMain({ token: data.token, userid: data.userId, email: data.email })
End Sub

' ---- main screen ------------------------------------------------------------

Sub showMain(auth as object)
    m.auth      = auth
    m.skipBack  = 10
    m.skipFwd   = 45
    loadSkipSettings()
    setNavTab(0)
    showSection(0)
    enterGrid()
End Sub

Sub loadSkipSettings()
    m.settingsTask = CreateObject("roSGNode", "RelayTask")
    m.settingsTask.observeField("response", "onSkipSettingsLoaded")
    m.settingsTask.bodyJson = FormatJSON({ action: "namedSettings", token: m.auth.token })
    m.settingsTask.control = "RUN"
End Sub

Sub onSkipSettingsLoaded()
    if m.settingsTask.status <> 200 then return
    data = ParseJSON(m.settingsTask.response)
    if data = invalid then return
    if data.skipBack <> invalid and data.skipBack > 0
        m.skipBack = CInt(data.skipBack)
    end if
    if data.skipForward <> invalid and data.skipForward > 0
        m.skipFwd = CInt(data.skipForward)
    end if
    updateControlsHint()
    print "[MainScene] skip settings back="; m.skipBack; " fwd="; m.skipFwd
End Sub

Sub setNavTab(index as integer)
    m.navIndex = index
    tabNames = ["Up Next", "New Releases", "Radio Favs", "Browse"]
    for i = 0 to 3
        if i = index
            m.tabs[i].font  = "font:MediumBoldSystemFont"
            m.tabs[i].color = "0xFFFFFFFF"
            m.tabLines[i].visible = true
        else
            m.tabs[i].font  = "font:MediumSystemFont"
            m.tabs[i].color = "0x9C9FA4FF"
            m.tabLines[i].visible = false
        end if
    end for
    updateKeyHints()
End Sub

Sub enterGrid()
    m.mode = "grid"
    m.gridIdx = 0
    m.top.setFocus(true)
    updateKeyHints()
End Sub

Sub enterNav()
    m.mode = "nav"
    m.top.setFocus(true)
    updateKeyHints()
End Sub

Sub enterNowPlaying()
    m.mode = "nowplaying"
    m.nowPlaying.visible = true
    m.keyHints.visible = false
    m.top.setFocus(true)
    updateKeyHints()
End Sub

' showSection: sets tab + loads data for that section
Sub showSection(index as integer)
    setNavTab(index)
    m.tileGrid.content = invalid
    setStatus("")
    if index = 0 or index = 1
        setPodcastGrid()
        if index = 0 then loadUpNext() else loadNewReleases()
    else
        setStationGrid()
        if index = 2 then loadFavorites() else loadBrowse()
    end if
End Sub

Sub setPodcastGrid()
    m.tileGrid.itemComponentName = "PodcastTileItem"
    m.tileGrid.itemSize          = [860, 90]
    m.tileGrid.itemSpacing       = [20, 10]
    m.tileGrid.numColumns        = 1
    m.tileGrid.numRows           = 6
    m.numColumns                 = 1
    m.podcastDetail.visible      = true
End Sub

Sub setStationGrid()
    m.tileGrid.itemComponentName = "TileItem"
    m.tileGrid.itemSize          = [270, 200]
    m.tileGrid.itemSpacing       = [20, 20]
    m.tileGrid.numColumns        = 6
    m.tileGrid.numRows           = 2
    m.numColumns                 = 6
    m.podcastDetail.visible      = false
End Sub

Sub updateDetailPanel(item as object)
    if not m.podcastDetail.visible then return
    if item = invalid then return
    m.detailArt.uri = item.HDPosterUrl
    m.detailTitle.text = item.title
    meta = ParseJSON(item.description)
    if meta = invalid then return
    m.detailPodcast.text = meta.podcastName
    m.detailDate.text    = meta.dateStr
    dur    = CInt(meta.duration)
    played = CInt(meta.playedUpTo)
    if played > 0
        left = dur - played
        m.detailTime.text = PodFmtDetail(dur) + "  ·  " + PodFmtDetail(left) + " left"
    else if dur > 0
        m.detailTime.text = PodFmtDetail(dur)
    else
        m.detailTime.text = ""
    end if
    notes = meta.showNotes
    if notes <> invalid and notes <> ""
        ' Strip basic HTML tags for plain-text display
        notes = notes.Replace("<p>", "").Replace("</p>", " ").Replace("<br>", " ").Replace("<br/>", " ").Replace("<br />", " ")
        notes = notes.Replace("&amp;", "&").Replace("&lt;", "<").Replace("&gt;", ">").Replace("&nbsp;", " ")
        m.detailDesc.text = notes
    else
        m.detailDesc.text = ""
    end if
End Sub

Function RelativeDate(isoStr as string) as string
    if isoStr = invalid or isoStr = "" then return ""
    pub = CreateObject("roDateTime")
    pub.FromISO8601String(isoStr)
    pubSecs = pub.AsSeconds()
    now = CreateObject("roDateTime")
    now.Mark()
    nowSecs = now.AsSeconds()
    diffSecs = nowSecs - pubSecs
    if diffSecs < 0 then return ""
    diffDays = int(diffSecs / 86400)
    if diffDays = 0 then return "Today"
    if diffDays = 1 then return "Yesterday"
    days = ["Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"]
    if diffDays < 7
        pub.Mark()
        pub.FromISO8601String(isoStr)
        return days[pub.GetDayOfWeek()]
    end if
    if diffDays < 14 then return "Last " + days[pub.GetDayOfWeek()]
    weeks = int(diffDays / 7)
    if weeks < 5 then return weeks.ToStr() + " weeks ago"
    months = int(diffDays / 30)
    if months = 1 then return "1 month ago"
    return months.ToStr() + " months ago"
End Function

Function PodFmtDetail(secs as integer) as string
    if secs <= 0 then return "0m"
    h    = secs \ 3600
    mins = (secs mod 3600) \ 60
    if h > 0 then return h.ToStr() + "h " + mins.ToStr() + "m"
    return mins.ToStr() + "m"
End Function

Sub updateKeyHints()
    if m.mode = "nav"
        if m.nowPlayingActive
            m.keyHints.text = "Left/Right  Switch tab   Down  Grid   Up  Now Playing   Back  Logout"
        else
            m.keyHints.text = "Left/Right  Switch tab   Down/OK  Enter grid   Back  Logout"
        end if
    else if m.mode = "grid"
        m.keyHints.text = "OK  Play   Left/Right  Move   Up/Back  Nav bar"
    else if m.mode = "nowplaying"
        m.keyHints.text = "Play  Play/Pause   Left/Right  Skip   Back  Return"
    end if
End Sub

Sub updateControlsHint()
    if m.nowPlayingActive = true
        if m.isCurrentlyLive
            m.controlsHint.text = "Play/Pause  (Play btn)"
        else
            m.controlsHint.text = "Play/Pause  (Play btn)   << " + m.skipBack.ToStr() + "s  (REW/Left)   " + m.skipFwd.ToStr() + "s >>  (FF/Right)"
        end if
    end if
End Sub

' ---- section data loaders ---------------------------------------------------

Sub loadUpNext()
    setStatus("Loading...")
    m.relay = CreateObject("roSGNode", "RelayTask")
    m.relay.observeField("response", "onUpNextLoaded")
    m.relay.bodyJson = FormatJSON({
        action: "upNext",
        token: m.auth.token,
        deviceId: m.deviceId
    })
    m.relay.control = "RUN"
End Sub

Sub onUpNextLoaded()
    if m.relay.status = 401 or m.relay.status = 403
        logout()
        return
    end if
    if m.relay.status <> 200
        setStatus("Failed to load Up Next. Check network.")
        return
    end if
    data = ParseJSON(m.relay.response)
    if data = invalid or data.episodes = invalid or data.episodes.count() = 0
        setStatus("Up Next is empty.")
        return
    end if
    m.upNextContent = data.episodes
    content = createObject("roSGNode", "ContentNode")
    for each ep in data.episodes
        child = content.createChild("ContentNode")
        child.title = ep.title
        child.url   = ep.url
        child.HDPosterUrl = "https://static.pocketcasts.com/discover/images/420/" + ep.podcast + ".jpg"
        pubStr = ep.published
        if type(pubStr) <> "String" then pubStr = ""
        child.description = FormatJSON({
            uuid:        ep.uuid,
            podcast:     ep.podcast,
            podcastName: ep.podcastName,
            playedUpTo:  ep.playedUpTo,
            duration:    ep.duration,
            published:   pubStr,
            dateStr:     RelativeDate(pubStr),
            showNotes:   "",
            isStation:   false
        })
        child.isNowPlaying = false
    end for
    m.tileGrid.content = content
    m.tileGrid.jumpToItem = 0
    m.gridIdx = 0
    setStatus("")
    firstItem = content.getChild(0)
    if firstItem <> invalid
        updateTopPanelMeta(firstItem)
        updateDetailPanel(firstItem)
    end if
    print "[MainScene] Up Next loaded count="; data.episodes.count()
End Sub

Sub loadNewReleases()
    setStatus("Loading...")
    m.relay = CreateObject("roSGNode", "RelayTask")
    m.relay.observeField("response", "onNewReleasesLoaded")
    m.relay.bodyJson = FormatJSON({ action: "newReleases", token: m.auth.token })
    m.relay.control = "RUN"
End Sub

Sub onNewReleasesLoaded()
    if m.relay.status = 401 or m.relay.status = 403
        logout()
        return
    end if
    if m.relay.status <> 200
        setStatus("Failed to load New Releases. Check network.")
        return
    end if
    data = ParseJSON(m.relay.response)
    if data = invalid or data.episodes = invalid or data.episodes.count() = 0
        setStatus("No new episodes in the last 14 days.")
        return
    end if
    content = createObject("roSGNode", "ContentNode")
    for each ep in data.episodes
        child = content.createChild("ContentNode")
        child.title = ep.title
        child.url   = ep.url
        child.HDPosterUrl = ep.artworkUrl
        pubStr = ep.published
        if type(pubStr) <> "String" then pubStr = ""
        notesStr = ep.showNotes
        if type(notesStr) <> "String" then notesStr = ""
        child.description = FormatJSON({
            uuid:        ep.uuid,
            podcast:     ep.podcast,
            podcastName: ep.podcastName,
            playedUpTo:  0,
            duration:    ep.duration,
            published:   pubStr,
            dateStr:     RelativeDate(pubStr),
            showNotes:   notesStr,
            isStation:   false
        })
        child.isNowPlaying = false
    end for
    m.tileGrid.content = content
    m.tileGrid.jumpToItem = 0
    m.gridIdx = 0
    setStatus("")
    firstItem = content.getChild(0)
    if firstItem <> invalid
        updateTopPanelMeta(firstItem)
        updateDetailPanel(firstItem)
    end if
    print "[MainScene] New Releases loaded count="; data.episodes.count()
End Sub

Sub loadFavorites()
    setStatus("Loading...")
    m.http = CreateObject("roSGNode", "HttpJsonTask")
    m.http.observeField("response", "onFavoritesLoaded")
    m.http.url = SupabaseUrl() + "/rest/v1/radio_favorites?select=station_id&user_uuid=eq." + m.auth.userid
    m.http.headers = { apikey: SupabaseAnonKey(), "x-user-uuid": m.auth.userid }
    m.http.control = "RUN"
End Sub

Sub onFavoritesLoaded()
    if m.http.status <> 200
        setStatus("Failed to load favorites.")
        return
    end if
    data = ParseJSON(m.http.response)
    if data = invalid or data.count() = 0
        setStatus("No favorites. Browse stations to add some.")
        m.tileGrid.content = invalid
        return
    end if
    ids = []
    for each fav in data
        ids.push(fav.station_id)
    end for
    m.resolvedStations = []
    m.resolveIndex = 0
    m.resolveIds = ids
    resolveNextStation()
End Sub

Sub resolveNextStation()
    if m.resolveIndex >= m.resolveIds.count()
        showStationGrid(m.resolvedStations)
        return
    end if
    id = m.resolveIds[m.resolveIndex]
    m.http = CreateObject("roSGNode", "HttpJsonTask")
    m.http.observeField("response", "onStationResolved")
    m.http.url = RadioBrowserUrl() + "/stations/byuuid/" + id
    m.http.headers = { "User-Agent": "PocketRadio/1.0" }
    m.http.control = "RUN"
End Sub

Sub onStationResolved()
    if m.http.status = 200
        data = ParseJSON(m.http.response)
        if data <> invalid and data.count() > 0
            station = data[0]
            if station.name <> invalid and station.name <> "" and station.url_resolved <> invalid and station.url_resolved <> ""
                m.resolvedStations.push(station)
            end if
        end if
    end if
    m.resolveIndex = m.resolveIndex + 1
    resolveNextStation()
End Sub

Sub loadBrowse()
    setStatus("Loading...")
    m.http = CreateObject("roSGNode", "HttpJsonTask")
    m.http.observeField("response", "onBrowseLoaded")
    m.http.url = RadioBrowserUrl() + "/stations/topvote?limit=50&hidebroken=true"
    m.http.headers = { "User-Agent": "PocketRadio/1.0" }
    m.http.control = "RUN"
End Sub

Sub onBrowseLoaded()
    if m.http.status <> 200
        setStatus("Failed to load stations.")
        return
    end if
    data = ParseJSON(m.http.response)
    if data = invalid
        setStatus("No stations found.")
        return
    end if
    showStationGrid(filterStations(data))
End Sub

Function filterStations(data as object) as object
    result = []
    for each station in data
        if station.name <> invalid and station.name <> "" and station.url_resolved <> invalid and station.url_resolved <> ""
            result.push(station)
        end if
    end for
    return result
End Function

Sub showStationGrid(stations as object)
    if stations.count() = 0
        setStatus("No stations.")
        m.tileGrid.content = invalid
        return
    end if
    content = createObject("roSGNode", "ContentNode")
    for each station in stations
        child = content.createChild("ContentNode")
        child.title = station.name
        child.url   = station.url_resolved
        artwork = StationArtwork(station.name)
        if artwork = ""
            favicon = station.favicon
            if favicon <> invalid and favicon <> "" and favicon.Instr(0, ".ico") < 0 and favicon.Instr(0, ".svg") < 0
                artwork = favicon
            end if
        end if
        child.HDPosterUrl = artwork
        meta = {
            stationuuid: station.stationuuid,
            isStation:   true,
            streamformat: inferStreamformat(station.url_resolved, station.codec)
        }
        if station.codec   <> invalid then meta.codec   = station.codec
        if station.bitrate <> invalid then meta.bitrate = station.bitrate
        if station.country <> invalid then meta.display = station.country
        child.description = FormatJSON(meta)
        child.isNowPlaying = false
    end for
    m.tileGrid.content = content
    m.tileGrid.jumpToItem = 0
    m.gridIdx = 0
    setStatus("")
    firstItem = content.getChild(0)
    if firstItem <> invalid
        updateTopPanelMeta(firstItem)
        updateDetailPanel(firstItem)
    end if
    print "[MainScene] station grid count="; stations.count()
End Sub

' ---- tile events ------------------------------------------------------------

Sub onTileFocused()
    idx = m.tileGrid.itemFocused
    m.gridIdx = idx
    print "[MainScene] tileFocused="; idx
    if m.tileGrid.content = invalid then return
    item = m.tileGrid.content.getChild(idx)
    if item = invalid then return
    updateTopPanelMeta(item)
    updateDetailPanel(item)
End Sub

Sub onFocusTimer()
    if m.pendingBackdropUrl = invalid or m.pendingBackdropUrl = "" then return
    m.backdrop.opacity = 0.0
    m.backdrop.uri = m.pendingBackdropUrl
    m.backdropFade.control = "start"
End Sub

Sub setNowBadge(idx as integer)
    if m.tileGrid.content = invalid then return
    count = m.tileGrid.content.getChildCount()
    for i = 0 to count - 1
        child = m.tileGrid.content.getChild(i)
        if child <> invalid then child.isNowPlaying = (i = idx)
    end for
End Sub

Sub updateTopPanelMeta(item as object)
    if not m.nowPlayingActive then return
    m.topTitle.text  = item.title
    artUrl = item.HDPosterUrl
    if artUrl <> invalid and artUrl <> ""
        m.topArt.uri = artUrl
        m.pendingBackdropUrl = artUrl
        m.focusTimer.control = "start"
    end if
    meta = ParseJSON(item.description)
    if meta = invalid then return
    if meta.isStation = true
        parts = []
        if meta.display <> invalid and meta.display <> "" then parts.push(meta.display)
        if meta.codec <> invalid and meta.codec <> ""
            codecStr = meta.codec
            if meta.bitrate <> invalid and meta.bitrate > 0
                codecStr = codecStr + " / " + meta.bitrate.ToStr() + " kbps"
            end if
            parts.push(codecStr)
        end if
        m.topSubtitle.text = parts.Join("  |  ")
        m.topDesc.text     = ""
    else
        m.topSubtitle.text = meta.podcastName
        dur = CInt(meta.duration)
        played = CInt(meta.playedUpTo)
        descParts = []
        if dur > 0
            if played > 0
                left = dur - played
                descParts.push(FmtDur(left) + " left")
            else
                descParts.push(FmtDur(dur))
            end if
        end if
        m.topDesc.text = descParts.Join("  ")
    end if
End Sub

Sub onTileSelected()
    idx = m.tileGrid.itemSelected
    selectGridItem(idx)
End Sub

Sub selectGridItem(idx as integer)
    print "[MainScene] tileSelected="; idx
    if m.tileGrid.content = invalid then return
    item = m.tileGrid.content.getChild(idx)
    if item = invalid then return
    meta = ParseJSON(item.description)
    if meta = invalid then return

    if meta.isStation = true
        playStation(item, meta)
    else
        if idx = 0 and m.navIndex = 0
            playEpisode(item)
        else
            m.pendingPlayItem = item
            setStatus("Queuing...")
            m.changeTask = CreateObject("roSGNode", "RelayTask")
            m.changeTask.observeField("response", "onPlayNowDone")
            m.changeTask.bodyJson = FormatJSON({
                action:   "upNextChange",
                token:    m.auth.token,
                change:   "playNow",
                deviceId: m.deviceId,
                uuid:     meta.uuid,
                title:    item.title,
                url:      item.url,
                podcast:  meta.podcast
            })
            m.changeTask.control = "RUN"
        end if
    end if
End Sub

Sub focusGridItem(idx as integer)
    if m.tileGrid.content = invalid then return
    count = m.tileGrid.content.getChildCount()
    if count = 0 then return
    if idx < 0 then idx = 0
    if idx >= count then idx = count - 1
    m.gridIdx = idx
    m.tileGrid.jumpToItem = idx
    item = m.tileGrid.content.getChild(idx)
    if item <> invalid
        updateTopPanelMeta(item)
        updateDetailPanel(item)
    end if
End Sub

Sub onPlayNowDone()
    print "[MainScene] playNow done status="; m.changeTask.status
    if m.pendingPlayItem <> invalid
        playEpisode(m.pendingPlayItem)
        m.pendingPlayItem = invalid
    end if
End Sub

' ---- playback ---------------------------------------------------------------

Sub playStation(item as object, meta as object)
    if m.audio = invalid
        m.audio = m.top.createChild("Audio")
        m.audio.observeField("state", "onAudioState")
    end if
    m.audio.control = "stop"

    fmt = "mp3"
    if meta.streamformat <> invalid and meta.streamformat <> "" then fmt = meta.streamformat
    audioContent = createObject("roSGNode", "ContentNode")
    audioContent.url = item.url
    audioContent.streamformat = fmt

    m.audio.content = invalid
    m.audio.content = audioContent
    m.audio.control = "play"

    isLive = (fmt <> "mp3")
    m.isCurrentlyLive  = isLive
    m.currentEpisode   = invalid
    m.currentStation   = item
    m.nowPlayingActive = true
    setNowBadge(m.gridIdx)

    showPlayingState(item.title, "", item.HDPosterUrl, isLive)
    stopTracklist()
    startTracklist(item.title)

    m.nowPlaying.trackTitle  = item.title
    m.nowPlaying.podcastName = ""
    m.nowPlaying.artworkUrl  = item.HDPosterUrl
    m.nowPlaying.isLive      = isLive
    m.nowPlaying.duration    = 0
    m.nowPlaying.skipBack    = m.skipBack
    m.nowPlaying.skipFwd     = m.skipFwd
    m.nowPlaying.playState   = "playing"

    parts = []
    if meta.display <> invalid and meta.display <> "" then parts.push(meta.display)
    if meta.codec <> invalid and meta.codec <> ""
        codecStr = meta.codec
        if meta.bitrate <> invalid and meta.bitrate > 0
            codecStr = codecStr + " / " + meta.bitrate.ToStr() + " kbps"
        end if
        parts.push(codecStr)
    end if
    m.nowPlaying.description = parts.Join("  |  ")
End Sub

Sub playEpisode(item as object)
    if m.audio = invalid
        m.audio = m.top.createChild("Audio")
        m.audio.observeField("state", "onAudioState")
    end if
    m.audio.control = "stop"

    meta = ParseJSON(item.description)
    audioContent = createObject("roSGNode", "ContentNode")
    audioContent.url = item.url
    audioContent.streamformat = inferStreamformat(item.url, "")

    playStart = 0
    if meta <> invalid and meta.playedUpTo <> invalid and meta.playedUpTo > 0
        playStart = meta.playedUpTo
    end if
    print "[MainScene] playEpisode playStart="; playStart; " duration="; meta.duration
    if playStart > 0 then audioContent.PlayStart = playStart

    m.audio.content = invalid
    m.audio.content = audioContent
    m.audio.control = "play"

    m.isCurrentlyLive  = false
    m.currentStation   = invalid
    m.nowPlayingActive = true
    setNowBadge(m.gridIdx)
    stopTracklist()

    podcastName = ""
    if meta <> invalid and meta.podcastName <> invalid then podcastName = meta.podcastName
    artUrl = "https://static.pocketcasts.com/discover/images/420/" + meta.podcast + ".jpg"
    m.currentEpisode = {
        uuid:        meta.uuid,
        podcast:     meta.podcast,
        podcastName: podcastName,
        title:       item.title,
        url:         item.url,
        duration:    meta.duration
    }

    showPlayingState(item.title, podcastName, artUrl, false)

    m.nowPlaying.trackTitle  = item.title
    m.nowPlaying.podcastName = podcastName
    m.nowPlaying.artworkUrl  = artUrl
    m.nowPlaying.isLive      = false
    m.nowPlaying.duration    = meta.duration
    m.nowPlaying.skipBack    = m.skipBack
    m.nowPlaying.skipFwd     = m.skipFwd
    m.nowPlaying.playState   = "playing"

    dur = CInt(meta.duration)
    played = CInt(meta.playedUpTo)
    descParts = []
    if dur > 0
        if played > 0
            left = dur - played
            descParts.push(FmtDur(left) + " left")
        else
            descParts.push(FmtDur(dur))
        end if
    end if
    m.nowPlaying.description = podcastName + "  |  " + descParts.Join("  ")

    m.lastSavedPosition = playStart
    if m.saveTimer = invalid
        m.saveTimer = m.top.createChild("Timer")
        m.saveTimer.duration = 30
        m.saveTimer.repeat   = true
        m.saveTimer.observeField("fire", "onSaveTimer")
    end if
    m.saveTimer.control = "start"

    if m.posTimer = invalid
        m.posTimer = m.top.createChild("Timer")
        m.posTimer.duration = 1
        m.posTimer.repeat   = true
        m.posTimer.observeField("fire", "onPosTimer")
    end if
    m.posTimer.control = "start"
End Sub

Sub showPlayingState(title as string, subtitle as string, artUrl as string, isLive as boolean)
    m.topTitle.text    = title
    m.topSubtitle.text = subtitle
    if artUrl <> invalid and artUrl <> ""
        m.topArt.uri       = artUrl
        m.backdrop.opacity = 0.0
        m.backdrop.uri     = artUrl
        m.backdropFade.control = "start"
    end if
    m.progressBg.visible   = not isLive
    m.progressFill.visible = not isLive
    m.timeLabel.visible    = not isLive
    m.controlsHint.visible = true
    updateControlsHint()
End Sub

Sub onSaveTimer()
    if m.audio = invalid or m.currentEpisode = invalid then return
    curPos = m.audio.position
    if curPos = invalid then return
    if curPos > m.lastSavedPosition + 5
        saveEpisodePosition(curPos, 2)
        m.lastSavedPosition = curPos
    end if
End Sub

Sub onPosTimer()
    if m.audio = invalid then return
    curPos = m.audio.position
    if curPos = invalid then return
    if m.currentEpisode <> invalid
        dur = m.currentEpisode.duration
        if dur > 0
            frac = curPos / dur
            if frac > 1.0 then frac = 1.0
            m.progressFill.width = Int(1760.0 * frac)
            left = dur - CInt(curPos)
            m.timeLabel.text = FmtDurHMS(CInt(curPos)) + "  /  " + FmtDurHMS(dur) + "  (" + FmtDur(left) + " left)"
        end if
    end if
    m.nowPlaying.playPos   = CInt(curPos)
    m.nowPlaying.playState = m.audio.state
End Sub

Sub saveEpisodePosition(position, status)
    if m.currentEpisode = invalid then return
    m.saveTask = CreateObject("roSGNode", "RelayTask")
    m.saveTask.observeField("response", "onEpisodeSaved")
    m.saveTask.bodyJson = FormatJSON({
        action:   "updateEpisode",
        token:    m.auth.token,
        uuid:     m.currentEpisode.uuid,
        podcast:  m.currentEpisode.podcast,
        position: Int(position),
        status:   status,
        duration: m.currentEpisode.duration
    })
    m.saveTask.control = "RUN"
End Sub

Sub onEpisodeSaved()
    print "[MainScene] Episode position saved."
End Sub

Sub removeFromUpNext(episode as object)
    m.changeTask = CreateObject("roSGNode", "RelayTask")
    m.changeTask.observeField("response", "onChangeDone")
    m.changeTask.bodyJson = FormatJSON({
        action:   "upNextChange",
        token:    m.auth.token,
        change:   "remove",
        deviceId: m.deviceId,
        uuid:     episode.uuid,
        title:    episode.title,
        url:      episode.url,
        podcast:  episode.podcast
    })
    m.changeTask.control = "RUN"
End Sub

Sub finishAndAdvance(episode as object)
    m.finishTask = CreateObject("roSGNode", "RelayTask")
    m.finishTask.observeField("response", "onFinishDone")
    m.finishTask.bodyJson = FormatJSON({
        action:   "finishEpisode",
        token:    m.auth.token,
        uuid:     episode.uuid,
        podcast:  episode.podcast,
        title:    episode.title,
        url:      episode.url,
        duration: episode.duration,
        deviceId: m.deviceId
    })
    m.finishTask.control = "RUN"
End Sub

Sub onFinishDone()
    print "[MainScene] finishEpisode done status="; m.finishTask.status
    advanceQueue()
End Sub

Sub onChangeDone()
    print "[MainScene] Up Next change applied."
End Sub

Sub advanceQueue()
    if m.navIndex = 0 and m.tileGrid.content <> invalid
        content = m.tileGrid.content
        if content.getChildCount() <= 1
            setStatus("Queue finished.")
            m.nowPlayingActive = false
            setNowBadge(-1)
            m.progressBg.visible   = false
            m.progressFill.visible = false
            m.timeLabel.visible    = false
            m.controlsHint.visible = false
            m.nowPlaying.visible   = false
            if m.mode = "nowplaying" then enterNav()
            return
        end if
        content.removeChildIndex(0)
        m.tileGrid.content = invalid
        m.tileGrid.content = content
        m.tileGrid.jumpToItem = 0
        nextItem = content.getChild(0)
        if nextItem <> invalid then playEpisode(nextItem)
    end if
End Sub

Sub onAudioState()
    if m.audio = invalid then return
    m.nowPlaying.playState = m.audio.state

    if m.audio.state = "finished"
        if m.currentEpisode <> invalid
            if m.saveTimer <> invalid then m.saveTimer.control = "stop"
            if m.posTimer  <> invalid then m.posTimer.control  = "stop"
            finishAndAdvance(m.currentEpisode)
        else if m.currentStation <> invalid
            setStatus("Stream ended.")
            m.nowPlayingActive = false
            setNowBadge(-1)
        end if
    else if m.audio.state = "paused" or m.audio.state = "stopped"
        if m.currentEpisode <> invalid
            curPos = m.audio.position
            if curPos = invalid then curPos = 0
            dur = m.currentEpisode.duration
            if dur > 0 and (dur - CInt(curPos)) <= 10
                finishAndAdvance(m.currentEpisode)
            else
                saveEpisodePosition(curPos, 2)
            end if
        end if
        if m.saveTimer <> invalid then m.saveTimer.control = "stop"
        stopTracklist()
    else if m.audio.state = "playing"
        if m.currentEpisode <> invalid and m.saveTimer <> invalid
            m.saveTimer.control = "start"
        end if
    else if m.audio.state = "error"
        stopTracklist()
        if m.saveTimer <> invalid then m.saveTimer.control = "stop"
        if m.posTimer  <> invalid then m.posTimer.control  = "stop"
        m.nowPlayingActive     = false
        setNowBadge(-1)
        m.nowPlaying.visible   = false
        m.progressBg.visible   = false
        m.progressFill.visible = false
        m.timeLabel.visible    = false
        m.controlsHint.visible = false
        setStatus("Playback error. Check network.")
        print "[MainScene] audio error"
        if m.mode = "nowplaying" then enterNav()
    end if
End Sub

' ---- favorites --------------------------------------------------------------

Sub addFavorite(stationId as string)
    m.http = CreateObject("roSGNode", "HttpJsonTask")
    m.http.observeField("response", "onFavoriteAdded")
    m.http.url    = SupabaseUrl() + "/rest/v1/radio_favorites"
    m.http.method = "POST"
    m.http.headers = {
        apikey: SupabaseAnonKey(),
        "x-user-uuid": m.auth.userid,
        "Content-Type": "application/json",
        "Prefer": "return=minimal,resolution=merge-duplicates"
    }
    m.http.body = FormatJSON({ user_uuid: m.auth.userid, station_id: stationId })
    m.http.control = "RUN"
End Sub

Sub onFavoriteAdded()
    if m.http.status >= 200 and m.http.status < 300
        setStatus("Added to favorites.")
    else
        setStatus("Failed to add favorite.")
    end if
End Sub

Sub removeFavorite(stationId as string)
    m.http = CreateObject("roSGNode", "HttpJsonTask")
    m.http.observeField("response", "onFavoriteRemoved")
    m.http.url    = SupabaseUrl() + "/rest/v1/radio_favorites?station_id=eq." + stationId + "&user_uuid=eq." + m.auth.userid
    m.http.method = "DELETE"
    m.http.headers = {
        apikey: SupabaseAnonKey(),
        "x-user-uuid": m.auth.userid,
        "Prefer": "return=minimal"
    }
    m.http.body = ""
    m.http.control = "RUN"
End Sub

Sub onFavoriteRemoved()
    if m.http.status >= 200 and m.http.status < 300
        setStatus("Removed from favorites.")
        if m.navIndex = 2 then loadFavorites()
    else
        setStatus("Failed to remove favorite.")
    end if
End Sub

' ---- tracklist --------------------------------------------------------------

Sub startTracklist(stationName as string)
    stopTracklist()
    nameLow = LCase(stationName)
    trackType = ""
    if nameLow.Instr(0, "kcrw") >= 0 then trackType = "kcrw"
    if nameLow.Instr(0, "kexp") >= 0 then trackType = "kexp"
    if trackType = "" then return
    m.tracklistType = trackType
    fetchTracklist()
    m.tracklistTimer = m.top.createChild("Timer")
    m.tracklistTimer.duration = 30
    m.tracklistTimer.repeat   = true
    m.tracklistTimer.observeField("fire", "onTracklistTimer")
    m.tracklistTimer.control = "start"
End Sub

Sub stopTracklist()
    if m.tracklistTimer <> invalid
        m.tracklistTimer.control = "stop"
        m.tracklistTimer = invalid
    end if
    m.tracklistType = ""
End Sub

Sub onTracklistTimer()
    fetchTracklist()
End Sub

Sub fetchTracklist()
    if m.tracklistType = "kcrw"
        m.trackHttp = CreateObject("roSGNode", "HttpJsonTask")
        m.trackHttp.observeField("response", "onTracklistLoaded")
        m.trackHttp.url = "https://tracklist-api.kcrw.com/Music/all/1?page_size=10"
        m.trackHttp.control = "RUN"
    else if m.tracklistType = "kexp"
        m.trackHttp = CreateObject("roSGNode", "HttpJsonTask")
        m.trackHttp.observeField("response", "onTracklistLoaded")
        m.trackHttp.url = "https://api.kexp.org/v2/plays/?limit=10"
        m.trackHttp.control = "RUN"
    end if
End Sub

Sub onTracklistLoaded()
    if m.trackHttp.status <> 200 then return
    data = ParseJSON(m.trackHttp.response)
    if data = invalid then return
    trackText = ""
    if m.tracklistType = "kcrw"
        if type(data) = "roArray" and data.count() > 0
            for each entry in data
                artist = entry.artist
                title  = entry.title
                if artist <> invalid and artist <> "" and artist <> "[BREAK]" and title <> invalid and title <> ""
                    trackText = title + " -- " + artist
                    exit for
                end if
            end for
        end if
    else if m.tracklistType = "kexp"
        results = data.results
        if results <> invalid and results.count() > 0
            for each entry in results
                if entry.play_type = "trackplay" and entry.song <> invalid and entry.song <> ""
                    artist = entry.artist
                    if artist = invalid then artist = ""
                    trackText = entry.song
                    if artist <> "" then trackText = trackText + " -- " + artist
                    exit for
                end if
            end for
        end if
    end if
    if trackText <> "" then m.topSubtitle.text = trackText
End Sub

' ---- utilities --------------------------------------------------------------

Function inferStreamformat(url as string, codec as string) as string
    if url <> invalid and url.Instr(".m3u8") >= 0 then return "hls"
    if codec <> invalid
        c = UCase(codec)
        if c = "AAC" or c = "AAC+" or c = "HE-AAC" or c = "AACPLUS" then return "aac"
        if c = "HLS" then return "hls"
    end if
    return "mp3"
End Function

Function FmtDur(secs as integer) as string
    h    = secs \ 3600
    mins = (secs Mod 3600) \ 60
    if h > 0 then return h.ToStr() + "h " + mins.ToStr() + "m"
    return mins.ToStr() + "m"
End Function

Function FmtDurHMS(secs as integer) as string
    h    = secs \ 3600
    mins = (secs Mod 3600) \ 60
    s    = secs Mod 60
    if h > 0 then return h.ToStr() + ":" + Pad2(mins) + ":" + Pad2(s)
    return mins.ToStr() + ":" + Pad2(s)
End Function

Function Pad2(n as integer) as string
    if n < 10 then return "0" + n.ToStr()
    return n.ToStr()
End Function

Function StripHtml(txt as string) as string
    result = CreateObject("roRegex", "<[^>]*>", "i").ReplaceAll(txt, "")
    result = result.Replace("&amp;",  "&")
    result = result.Replace("&lt;",   "<")
    result = result.Replace("&gt;",   ">")
    result = result.Replace("&quot;", Chr(34))
    result = result.Replace("&#39;",  "'")
    result = result.Replace("&nbsp;", " ")
    result = result.Replace("&hellip;", "...")
    result = CreateObject("roRegex", "\n\n+", "").ReplaceAll(result, Chr(10))
    return result.Trim()
End Function

Function StationArtwork(name as string) as string
    n = LCase(name)
    if n.Instr(0, "kcrw") >= 0
        return "pkg:/images/kcrw_logo.png"
    else if n.Instr(0, "kexp") >= 0
        return "pkg:/images/kexp_logo.png"
    end if
    return ""
End Function

Sub setStatus(text as string)
    m.gridStatus.text    = text
    m.gridStatus.visible = (text <> "")
End Sub

' ---- logout -----------------------------------------------------------------

Sub logout()
    if m.audio <> invalid then m.audio.control = "stop"
    if m.saveTimer <> invalid then m.saveTimer.control = "stop"
    if m.posTimer  <> invalid then m.posTimer.control  = "stop"
    stopTracklist()
    m.nowPlayingActive     = false
    m.nowPlaying.visible   = false
    m.progressBg.visible   = false
    m.progressFill.visible = false
    m.timeLabel.visible    = false
    m.controlsHint.visible = false
    m.tileGrid.content     = invalid
    m.currentEpisode       = invalid
    m.currentStation       = invalid
    AuthClear()
    m.auth = invalid
    m.top.setFocus(true)
    promptEmail()
End Sub

' ---- key events -------------------------------------------------------------

Function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false

    if m.mode = "nav"
        if key = "left"
            if m.navIndex > 0
                setNavTab(m.navIndex - 1)
            end if
            return true
        else if key = "right"
            if m.navIndex < 3
                setNavTab(m.navIndex + 1)
            end if
            return true
        else if key = "down" or key = "OK"
            showSection(m.navIndex)
            enterGrid()
            return true
        else if key = "up"
            if m.nowPlayingActive
                enterNowPlaying()
            end if
            return true
        else if key = "rewind" or key = "fastforward"
            if m.nowPlayingActive and m.audio <> invalid and not m.isCurrentlyLive
                curPos = m.audio.getField("position")
                if key = "rewind"
                    seekPos = curPos - m.skipBack
                    if seekPos < 0 then seekPos = 0
                    m.audio.seek = seekPos
                else
                    m.audio.seek = curPos + m.skipFwd
                end if
            end if
            return true
        else if key = "back"
            showLogoutDialog()
            return true
        end if

    else if m.mode = "grid"
        count = 0
        if m.tileGrid.content <> invalid then count = m.tileGrid.content.getChildCount()

        if key = "back" or key = "up"
            row = m.gridIdx \ m.numColumns
            if row > 0 and count > 0
                focusGridItem(m.gridIdx - m.numColumns)
            else
                print "[MainScene] grid back/up -> enterNav"
                enterNav()
            end if
            return true
        else if key = "down"
            if count > 0
                newIdx = m.gridIdx + m.numColumns
                if newIdx < count then focusGridItem(newIdx)
            end if
            return true
        else if key = "left"
            if m.gridIdx > 0
                focusGridItem(m.gridIdx - 1)
            end if
            return true
        else if key = "right"
            if count > 0 and m.gridIdx < count - 1
                focusGridItem(m.gridIdx + 1)
            end if
            return true
        else if key = "OK"
            if count > 0 then selectGridItem(m.gridIdx)
            return true
        else if key = "play"
            if m.audio <> invalid
                if m.audio.state = "playing"
                    m.audio.control = "pause"
                else
                    m.audio.control = "resume"
                end if
            end if
            return true
        else if key = "rewind" or key = "fastforward"
            if m.audio <> invalid and not m.isCurrentlyLive
                curPos = m.audio.getField("position")
                if key = "rewind"
                    seekPos = curPos - m.skipBack
                    if seekPos < 0 then seekPos = 0
                    m.audio.seek = seekPos
                else
                    m.audio.seek = curPos + m.skipFwd
                end if
            end if
            return true
        end if

    else if m.mode = "nowplaying"
        if key = "back"
            m.nowPlaying.visible = false
            m.keyHints.visible = true
            enterNav()
            return true
        else if key = "play" or key = "OK"
            if m.audio <> invalid
                if m.audio.state = "playing"
                    m.audio.control = "pause"
                else
                    m.audio.control = "resume"
                end if
            end if
            return true
        else if key = "left" or key = "rewind"
            if m.audio <> invalid and not m.isCurrentlyLive
                seekPos = m.audio.getField("position") - m.skipBack
                if seekPos < 0 then seekPos = 0
                m.audio.seek = seekPos
            end if
            return true
        else if key = "right" or key = "fastforward"
            if m.audio <> invalid and not m.isCurrentlyLive
                m.audio.seek = m.audio.getField("position") + m.skipFwd
            end if
            return true
        end if

    else if m.mode = "logout_confirm"
        return false
    end if

    return false
End Function

Sub showLogoutDialog()
    m.mode = "logout_confirm"
    dlg = CreateObject("roSGNode", "Dialog")
    dlg.title = "Log Out"
    dlg.message = "Log out of Pocket Casts?"
    dlg.buttons = ["Log Out", "Cancel"]
    m.dlg = dlg
    dlg.observeField("buttonSelected", "onLogoutBtn")
    dlg.observeField("wasClosed",      "onLogoutClosed")
    m.top.dialog = dlg
End Sub

Sub onLogoutBtn()
    btn = m.dlg.buttonSelected
    closeDialog()
    if btn = 0
        logout()
    else
        enterNav()
    end if
End Sub

Sub onLogoutClosed()
    if m.mode = "logout_confirm" then enterNav()
End Sub
