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
    // No `Tabs`: both of its modes clipped the page ~320px above the bar, so no
    // content ever painted underneath and the material had nothing to blur.
    // A Stack renders each page full-height and floats the bar on top.
    Stack({ alignContent: Alignment.Bottom }) {
      if (this.activeTab === 0) {
        Sessions()
      } else if (this.activeTab === 1) {
        Devices()
      } else {
        SettingsPage()
      }

      Row({ space: 2 }) {
        this.BarItem('Sessions', 0)
        this.BarItem('Devices', 1)
        this.BarItem('Settings', 2)
      }
      .padding(Theme.spaceXs)
      .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
      .borderRadius(Theme.radiusPill)
      .margin({ bottom: Theme.spaceXl })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.bg)
    .clip(false)
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

}
