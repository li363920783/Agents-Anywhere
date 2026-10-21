import { ApiClient } from '../core/net/ApiClient';
import { ApiError } from '../core/net/ApiError';
import { Fmt } from '../core/util/Fmt';
import { ConnectorListResponse, ConnectorView } from '../core/model/Connector';
import { Theme } from '../core/ui/Theme';

@Component
export struct Devices {
  @Consume('rootStack') rootStack: NavPathStack;
  @State items: Array<ConnectorView> = [];
  @State loading: boolean = false;
  @State errorMsg: string = '';

  async aboutToAppear(): Promise<void> {
    await this.load();
  }

  async load(): Promise<void> {
    this.loading = true;
    this.errorMsg = '';
    try {
      const res = await ApiClient.shared.get('/connectors');
      this.items = ConnectorListResponse.fromJson(res).connectors;
    } catch (e) {
      const err = e as Error;
      const msg = err instanceof ApiError ? err.message : 'load failed';
      this.errorMsg = msg;
    } finally {
      this.loading = false;
    }
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Text('Devices')
          .fontSize(Theme.fontTitle)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.text)
          .layoutWeight(1)
        Button('Refresh')
          .fontSize(Theme.fontTiny)
          .height(30)
          .backgroundColor(Theme.raised)
          .fontColor(Theme.text)
          .border({ width: 1, color: Theme.border })
          .borderRadius(Theme.radiusPill)
          .onClick(() => this.load())
      }
      .width(Theme.gutter)
      .padding({ top: 12, bottom: 10 })

      if (this.errorMsg.length > 0) {
        Text(this.errorMsg)
          .fontSize(Theme.fontSmall)
          .fontColor(Theme.danger)
          .width(Theme.gutter)
          .padding(8)
          .wordBreak(WordBreak.BREAK_ALL)
      }

      if (this.items.length === 0 && !this.loading) {
        Column() {
          Text('No connectors yet')
            .fontSize(Theme.fontSmall)
            .fontColor(Theme.faint)
            .margin({ top: 60 })
        }
        .layoutWeight(1)
      } else {
        List({ space: 8 }) {
          ForEach(this.items, (c: ConnectorView) => {
            ListItem() {
              Column({ space: 8 }) {
                Row({ space: 8 }) {
                  Circle({ width: 8, height: 8 })
                    .fill(c.online ? Theme.accent : Theme.faint)
                    .margin({ top: 5 })
                  Text(c.name)
                    .fontSize(Theme.fontBody)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(Theme.text)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .layoutWeight(1)
                  Text(c.online ? 'Online' : 'Offline')
                    .fontSize(Theme.fontTiny)
                    .fontColor(c.online ? Theme.accent : Theme.faint)
                    .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                    .backgroundColor(Theme.bg)
                    .borderRadius(Theme.radiusPill)
                }
                .width('100%')
                .alignItems(VerticalAlign.Top)

                Row({ space: 6 }) {
                  if (c.deviceOs.length > 0) {
                    Text(c.deviceOs)
                      .fontSize(Theme.fontTiny)
                      .fontColor(Theme.muted)
                      .fontFamily('monospace')
                    Text('·').fontSize(Theme.fontTiny).fontColor(Theme.borderStrong)
                  }
                  if (c.connectorKind.length > 0) {
                    Text(c.connectorKind)
                      .fontSize(Theme.fontTiny)
                      .fontColor(Theme.muted)
                    Text('·').fontSize(Theme.fontTiny).fontColor(Theme.borderStrong)
                  }
                  if (c.machine.length > 0) {
                    Text(c.machine)
                      .fontSize(Theme.fontTiny)
                      .fontColor(Theme.muted)
                      .fontFamily('monospace')
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .layoutWeight(1)
                    Text('·').fontSize(Theme.fontTiny).fontColor(Theme.borderStrong)
                  }
                  Text(Fmt.relTime(c.lastSeenAt, Date.now()))
                    .fontSize(Theme.fontTiny)
                    .fontColor(Theme.faint)
                }
                .width('100%')
              }
              .width('100%')
              .padding({ left: 14, right: 14, top: 12, bottom: 12 })
              .backgroundColor(Theme.surface)
              .border({ width: 1, color: Theme.border })
              .borderRadius(Theme.radiusCard)
              .alignItems(HorizontalAlign.Start)
            }
          }, (c: ConnectorView) => c.id)
        }
        .width(Theme.gutter)
        .layoutWeight(1)
        .padding({ top: 8, bottom: Theme.barClearance })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.bg)
  }
}
