Sub init()
    m.bg = m.top.findNode("bg")
    m.title = m.top.findNode("title")
    m.podcast = m.top.findNode("podcast")
    m.progress = m.top.findNode("progress")
End Sub

Sub onFocus()
    if m.top.focusPercent > 0.5
        m.bg.color = "0x1E333DFF"
        m.title.font = "font:LargeBoldSystemFont"
    else
        m.bg.color = "0x292B2EFF"
        m.title.font = "font:LargeSystemFont"
    end if
End Sub

Sub onContentSet()
    if m.top.itemContent <> invalid
        m.title.text = m.top.itemContent.title
        meta = ParseJSON(m.top.itemContent.description)
        if meta <> invalid
            if meta.podcastName <> invalid and meta.podcastName <> ""
                m.podcast.text = meta.podcastName
            else
                m.podcast.text = ""
            end if
            if meta.duration > 0
                if meta.playedUpTo > 0
                    left = meta.duration - meta.playedUpTo
                    m.progress.text = FormatTime(left) + " left"
                else
                    m.progress.text = FormatTime(meta.duration)
                end if
            else
                m.progress.text = ""
            end if
        end if
    end if
End Sub

Function FormatTime(seconds as integer) as string
    m = seconds \ 60
    s = seconds Mod 60
    return m.ToStr() + ":" + ZeroPad(s)
End Function

Function ZeroPad(n as integer) as string
    if n < 10
        return "0" + n.ToStr()
    else
        return n.ToStr()
    end if
End Function
