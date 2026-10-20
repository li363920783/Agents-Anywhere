import { promptAction } from '@kit.ArkUI';
import { ApiClient } from '../core/net/ApiClient';
import { AppState } from '../core/AppState';
import { Prefs } from '../core/store/Prefs';
import { Theme } from '../core/ui/Theme';

@Component
export struct SettingsPage {
  @Consume('rootStack') rootStack: NavPathStack;

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
