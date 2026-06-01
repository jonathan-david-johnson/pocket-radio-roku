Sub init()
    m.list = m.top.findNode("list")
    m.list.observeField("itemSelected", "onItemSelected")
    m.list.observeField("itemFocused", "onItemFocused")
End Sub

Sub onItemSelected()
    print "[StationList] itemSelected="; m.list.itemSelected
    m.top.itemSelected = m.list.itemSelected
End Sub

Sub onItemFocused()
    print "[StationList] itemFocused="; m.list.itemFocused
    m.top.itemFocused = m.list.itemFocused
End Sub