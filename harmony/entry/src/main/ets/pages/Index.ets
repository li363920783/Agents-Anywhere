import util from '@ohos.util';
import { AppState } from '../core/AppState';
import { Login } from './Login';
import { Sessions } from './Sessions';
import { SessionDetail } from './SessionDetail';
import { Devices } from './Devices';
import { SettingsPage } from './SettingsPage';
import { Workspace } from './Workspace';
import { SessionDetailParam } from '../core/model/Nav';
import { WorkspaceParam } from '../core/model/Workspace';
import { Theme } from '../core/ui/Theme';

/** EntryAbility publishes a notification-tap target here. */
const OPEN_SESSION_KEY = 'aa_open_session';

@Entry
@Component
struct Index {
  @Provide('rootStack') rootStack: NavPathStack = new NavPathStack();
  @StorageLink('aa_signed_in') signedIn: boolean = false;
  @StorageLink(OPEN_SESSION_KEY) @Watch('drainOpenSession') openSession: string = '';
  @State restoreDone: boolean = false;

  async aboutToAppear(): Promise<void> {
    if (!AppState.shared.signedIn) {
      await AppState.shared.restore();
    }
    this.signedIn = AppState.shared.signedIn;
    this.restoreDone = true;
    this.drainOpenSession();
  }

  /**
   * A notification tap only names a session id; the route can only be pushed
   * once restore has finished, so a cold start re-runs this after `restoreDone`.
   */
  private drainOpenSession(): void {
    if (this.openSession.length === 0 || !this.signedIn) {
      return;
    }
    const param = new SessionDetailParam();
    param.id = this.openSession;
    AppStorage.setOrCreate(OPEN_SESSION_KEY, '');
    this.rootStack.pushPath(new NavPathInfo('SessionDetail', param));
  }

  // Each branch must root in NavDestination: the Navigation drops any other root,
  // leaving a blank page with only a back button.
  @Builder
  PageMap(name: string, param: Object) {
    if (name === 'SessionDetail') {
      // The page draws its own header and back control; the system title bar
      // would otherwise sit above it as an empty strip.
      NavDestination() {
        SessionDetail({ sessionId: (param as SessionDetailParam).id })
      }
      .hideTitleBar(true)
      .backgroundColor(Theme.bg)
    } else if (name === 'Workspace') {
      NavDestination() {
        Workspace({
          connectorId: (param as WorkspaceParam).connectorId,
          root: (param as WorkspaceParam).root,
          title: (param as WorkspaceParam).title
        })
      }
      .hideTitleBar(true)
      .backgroundColor(Theme.bg)
    } else if (name === 'Devices') {
      NavDestination() {
        Devices()
      }
      .backgroundColor(Theme.bg)
    } else if (name === 'SettingsPage') {
      NavDestination() {
        SettingsPage()
      }
      .backgroundColor(Theme.bg)
    }
  }

  build() {
    Navigation(this.rootStack) {
      Stack() {
        if (this.restoreDone && this.signedIn) {
          MainTabs()
        } else if (this.restoreDone) {
          Login()
        } else {
          Column() {
            Text('Agents Anywhere').fontSize(Theme.fontHeading).fontColor(Theme.faint)
          }
          .width('100%')
          .height('100%')
          .backgroundColor(Theme.bg)
          .justifyContent(FlexAlign.Center)
        }
      }
    }
    .hideTitleBar(true)
    .mode(NavigationMode.Auto)
    .navDestination(this.PageMap)
    .onAppear(() => {
      this.signedIn = AppState.shared.signedIn;
    })
  }
}

@Component
struct MainTabs {
  @Consume('rootStack') rootStack: NavPathStack;
  @State activeTab: number = 0;

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Tabs({ index: this.activeTab }) {
        TabContent() {
          Sessions()
        }
        .tabBar(this.TabItem('Sessions', 0))

        TabContent() {
          Devices()
        }
        .tabBar(this.TabItem('Devices', 1))

        TabContent() {
          SettingsPage()
        }
        .tabBar(this.TabItem('Settings', 2))
      }
      // The built-in bar reserves its own strip, so content can never run under
      // it and the material has nothing to blur. Hide it and draw the bar here.
      .barHeight(0)
      .backgroundColor(Theme.bg)
      .onChange((index: number) => {
        this.activeTab = index;
      })

      Row({ space: 2 }) {
        this.BarItem('Sessions', 0)
        this.BarItem('Devices', 1)
        this.BarItem('Settings', 2)
      }
      .padding(Theme.spaceXs)
      // Real frosted glass: whatever the list scrolls behind gets blurred.
      .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
      .borderRadius(Theme.radiusPill)
      .margin({ bottom: Theme.spaceXl })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.bg)
  }

  @Builder
  BarItem(label: string, index: number) {
    Text(label)
      .fontSize(Theme.fontTiny)
      .fontWeight(this.activeTab === index ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.activeTab === index ? Theme.accent : Theme.faint)
      .padding({ left: 18, right: 18, top: 9, bottom: 9 })
      .borderRadius(Theme.radiusPill)
      .backgroundColor(this.activeTab === index ? Theme.raised : Color.Transparent)
      .onClick(() => {
        this.activeTab = index;
      })
  }

  // The unread count lives in the Sessions header, not here: a `tabBar` builder
  // re-runs but only renders its own text, so an added badge never appeared.
  @Builder
  TabItem(label: string, index: number) {
    Column() {
      Text(label)
        .fontSize(Theme.fontTiny)
        .fontWeight(this.activeTab === index ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.activeTab === index ? Theme.accent : Theme.faint)
    }
    .width('100%')
    .height(52)
    .justifyContent(FlexAlign.Center)
  }
}
