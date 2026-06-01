Sub init()
    m.bg = m.top.findNode("bg")
    m.name = m.top.findNode("name")
End Sub

Sub onFocus()
    if m.top.focusPercent > 0.5
        m.bg.color = "0x1E333DFF"
        m.name.font = "font:LargeBoldSystemFont"
    else
        m.bg.color = "0x292B2EFF"
        m.name.font = "font:LargeSystemFont"
    end if
End Sub

Sub onContentSet()
    if m.top.itemContent <> invalid
        m.name.text = m.top.itemContent.title
    end if
End Sub
