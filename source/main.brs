' PocketStreams — channel entry point.
' Creates the SceneGraph screen and hands off to MainScene.
Sub Main()
    print "[main] PocketStreams starting"
    screen = CreateObject("roSGScreen")
    port = CreateObject("roMessagePort")
    screen.setMessagePort(port)

    scene = screen.CreateScene("MainScene")
    screen.show()

    while true
        msg = wait(0, port)
        if type(msg) = "roSGScreenEvent"
            if msg.isScreenClosed()
                print "[main] screen closed, exiting"
                return
            end if
        end if
    end while
End Sub
