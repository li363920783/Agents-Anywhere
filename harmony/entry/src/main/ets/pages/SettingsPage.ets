import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { ApiClient } from '../core/net/ApiClient';
import { AppState } from '../core/AppState';
import { Notifier } from '../core/notify/Notifier';
import { LiveView } from '../core/notify/LiveView';
import { Prefs } from '../core/store/Prefs';
import { Theme } from '../core/ui/Theme';

@Component
export struct SettingsPage {
  @Consume('rootStack') rootStack: NavPathStack;
  @State notifyApproval: boolean = Prefs.getBool(Prefs.keys.notifyApproval, true);
  @State notifyDone: boolean = Prefs.getBool(Prefs.keys.notifyDone, true);
  /** OS-level switch; the two toggles below are inert while this is off. */
  @State notifyGranted: boolean = true;
  /** 实况窗 needs a per-app entitlement from Huawei before anything shows. */
  @State liveViewOn: boolean = false;

  aboutToAppear(): void {
    void Notifier.isEnabled().then((ok: boolean) => {
      this.notifyGranted = ok;
    });
    void LiveView.available().then((ok: boolean) => {
      this.liveViewOn = ok;
    });
  }

  private async askPermission(): Promise<void> {
    const ok = await Notifier.requestEnable(getContext(this) as common.UIAbilityContext);
    this.notifyGranted = ok;
    if (!ok) {
      promptAction.showToast({ message: 'Enable notifications in system settings', duration: 2000 });
    }
  }

  private async confirmSignOut(): Promise<void> {
    AlertDialog.show({
      title: 'Sign out',
      message: 'Remove the stored token from this device?',
      buttons: [
        {
          value: 'Sign out',
          fontColor: Theme.danger,
          action: () => {
            void this.doSignOut();
          }
        },
        {
          value: 'Cancel',
          action: () => {}
        }
      ]
    });
  }

  private async doSignOut(): Promise<void> {
    await AppState.shared.signOut();
    AppStorage.set('aa_signed_in', false);
    promptAction.showToast({ message: 'Signed out', duration: 1500 });
  }

  build() {
    Column() {
      Text('Settings')
        .fontSize(Theme.fontTitle)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.text)
        .width(Theme.gutter)
        .padding({ top: 12, bottom: 12 })

      Column({ space: 14 }) {
        Row() {
          Text('Server')
            .fontSize(Theme.fontSmall)
            .fontColor(Theme.faint)
            .layoutWeight(1)
          Text(AppState.shared.serverUrl)
            .fontSize(Theme.fontSmall)
            .fontColor(Theme.text)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .wordBreak(WordBreak.BREAK_ALL)
            .layoutWeight(2)
        }
        .alignItems(VerticalAlign.Top)

        Divider().color(Theme.border)

        Row() {
          Text('Account')
            .fontSize(Theme.fontSmall)
            .fontColor(Theme.faint)
            .layoutWeight(1)
          Text(AppState.shared.user?.displayName ?? '-')
            .fontSize(Theme.fontSmall)
            .fontColor(Theme.text)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .wordBreak(WordBreak.BREAK_ALL)
            .layoutWeight(2)
        }
        .alignItems(VerticalAlign.Top)

        Divider().color(Theme.border)

        Row() {
          Text('Email')
            .fontSize(Theme.fontSmall)
            .fontColor(Theme.faint)
            .layoutWeight(1)
          Text(AppState.shared.user?.email ?? '-')
            .fontSize(Theme.fontSmall)
            .fontColor(Theme.text)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .wordBreak(WordBreak.BREAK_ALL)
            .layoutWeight(2)
        }
        .alignItems(VerticalAlign.Top)
      }
      .width(Theme.gutter)
      .padding(16)
      .backgroundColor(Theme.surface)
      .borderRadius(Theme.radiusCard)
      .alignItems(HorizontalAlign.Start)

      Text('Notifications')
        .fontSize(Theme.fontTiny)
        .fontColor(Theme.faint)
        .width(Theme.gutter)
        .padding({ top: 20, bottom: 8 })

      Column({ space: 14 }) {
        Row() {
          Column({ space: 3 }) {
            Text('System permission')
              .fontSize(Theme.fontSmall)
              .fontColor(Theme.text)
            Text(this.notifyGranted ? 'Notifications are allowed' : 'Blocked by the system — tap to allow')
              .fontSize(Theme.fontTiny)
              .fontColor(this.notifyGranted ? Theme.faint : Theme.warn)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          if (!this.notifyGranted) {
            Text('Allow')
              .fontSize(Theme.fontTiny)
              .fontColor(Theme.accent)
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .border({ width: 1, color: Theme.accent })
              .borderRadius(Theme.radiusPill)
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          void this.askPermission();
        })

        Divider().color(Theme.border)

        Row() {
          Column({ space: 3 }) {
            Text('Needs approval')
              .fontSize(Theme.fontSmall)
              .fontColor(Theme.text)
            Text('A session is waiting for your confirmation')
              .fontSize(Theme.fontTiny)
              .fontColor(Theme.faint)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Toggle({ type: ToggleType.Switch, isOn: this.notifyApproval })
            .selectedColor(Theme.accent)
            .onChange((v: boolean) => {
              this.notifyApproval = v;
              Prefs.putBool(Prefs.keys.notifyApproval, v);
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Divider().color(Theme.border)

        Row() {
          Column({ space: 3 }) {
            Text('Turn finished')
              .fontSize(Theme.fontSmall)
              .fontColor(Theme.text)
            Text('An agent stopped working while you were away')
              .fontSize(Theme.fontTiny)
              .fontColor(Theme.faint)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Toggle({ type: ToggleType.Switch, isOn: this.notifyDone })
            .selectedColor(Theme.accent)
            .onChange((v: boolean) => {
              this.notifyDone = v;
              Prefs.putBool(Prefs.keys.notifyDone, v);
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Divider().color(Theme.border)

        Row() {
          Column({ space: 3 }) {
            Text('实况窗')
              .fontSize(Theme.fontSmall)
              .fontColor(Theme.text)
            Text(this.liveViewOn
              ? '已开通：回合运行时显示在锁屏和状态栏'
              : '未开通：需在华为 AGC 为该应用申请实况窗权益')
              .fontSize(Theme.fontTiny)
              .fontColor(this.liveViewOn ? Theme.faint : Theme.warn)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Text(this.liveViewOn ? '可用' : '未开通')
            .fontSize(Theme.fontTiny)
            .fontColor(this.liveViewOn ? Theme.accent : Theme.warn)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .width(Theme.gutter)
      .padding(16)
      .backgroundColor(Theme.surface)
      .borderRadius(Theme.radiusCard)
      .alignItems(HorizontalAlign.Start)

      Button('Sign out')
        .width(Theme.gutter)
        .height(46)
        .fontSize(Theme.fontBody)
        .margin({ top: 16 })
        .backgroundColor(Theme.dangerSurface)
        .fontColor(Theme.danger)
        .border({ width: 1, color: Theme.danger })
        .borderRadius(10)
        .onClick(() => this.confirmSignOut())

      Text('Agents Anywhere for HarmonyOS NEXT · ArkTS')
        .fontSize(Theme.fontTiny)
        .fontColor(Theme.faint)
        .margin({ top: 24 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.bg)
  }
}
