import util from '@ohos.util';
import { promptAction, router } from '@kit.ArkUI';
import { ApiClient } from '../core/net/ApiClient';
import { ApiError } from '../core/net/ApiError';
import { PasswordVerifier } from '../core/crypto/PasswordVerifier';
import { AppState } from '../core/AppState';
import { AuthUser } from '../core/model/Auth';
import { Json } from '../core/util/Json';
import { Prefs } from '../core/store/Prefs';
import { Theme } from '../core/ui/Theme';
import {
  EmptyBody,
  LoginRequest,
  MobileLoginConfirmRequest,
  MobileLoginExchangeRequest,
  MobileLoginRequest,
  MobileLoginStatusRequest,
  PasswordSaltRequest
} from '../core/model/Bodies';

const DEFAULT_SERVER = 'https://web.agents-anywhere.com';

@Component
export struct Login {
  @State serverUrl: string = DEFAULT_SERVER;
  @State serverOk: boolean = false;
  @State serverHint: string = 'Check the server before signing in.';
  @State email: string = '';
  @State password: string = '';
  @State busy: boolean = false;
  @State qrOpen: boolean = false;
  @State qrText: string = '';

  async aboutToAppear(): Promise<void> {
    const saved = Prefs.getString(Prefs.keys.serverUrl, '');
    if (saved.length > 0) {
      this.serverUrl = saved;
    }
  }

  private toast(msg: string): void {
    promptAction.showToast({ message: msg, duration: 2000 });
  }

  private async checkServer(): Promise<void> {
    if (this.serverUrl.trim().length === 0) {
      this.serverHint = 'Enter a server URL.';
      return;
    }
    try {
      ApiClient.configure(this.serverUrl, '');
      const cfg = await ApiClient.shared.get('/auth/config', false);
      this.serverOk = true;
      this.serverHint = Json.bool(cfg, 'registrationOpen') === true
        ? 'Server reachable'
        : 'Server reachable (login only)';
    } catch (e) {
      this.serverOk = false;
      const err = e as Error;
      const code = err instanceof ApiError ? err.httpCode : 0;
      this.serverHint = `Unreachable (${code})`;
    }
  }

  private async signIn(): Promise<void> {
    if (!this.serverOk || this.email.trim().length === 0 || this.password.length === 0) {
      this.toast('Check the server and fill both credentials.');
      return;
    }
    this.busy = true;
    try {
      const saltBody = new PasswordSaltRequest();
      saltBody.email = this.email.trim().toLowerCase();
      const saltRes = await ApiClient.shared.post('/auth/password-salt', saltBody, false);
      const salt = Json.strOr(saltRes, 'salt', '');
      const verifier = await PasswordVerifier.derive(this.password, salt);
      const loginBody = new LoginRequest();
      loginBody.email = this.email.trim().toLowerCase();
      loginBody.passwordVerifier = verifier;
      const res = await ApiClient.shared.post('/auth/login', loginBody, false);
      const user = AuthUser.fromJson(res);
      const token = Json.strOr(res, 'accessToken', '');
      await AppState.shared.signIn(this.serverUrl, token, user);
      this.toast(`Signed in as ${user.displayName}`);
    } catch (e) {
      const err = e as Error;
      const msg = err instanceof ApiError ? err.message : 'sign-in failed';
      this.toast(msg);
    } finally {
      this.busy = false;
    }
  }

  private async qrLogin(): Promise<void> {
    let payload: Object | null = null;
    try {
      payload = JSON.parse(this.qrText.trim()) as Object;
    } catch {
      this.toast('Not valid JSON.');
      return;
    }
    if (payload === null) {
      return;
    }
    const server = Json.str(payload, 'serverUrl') ?? Json.str(payload, 'server') ?? '';
    const userId = Json.strOr(payload, 'userId', Json.strOr(payload, 'loginId', ''));
    const loginToken = Json.strOr(payload, 'loginToken', '');
    if (server.length === 0 || userId.length === 0 || loginToken.length === 0) {
      this.toast('QR payload missing server/userId/loginToken.');
      return;
    }
    this.busy = true;
    try {
      ApiClient.configure(server, '');
      const reqBody = new MobileLoginRequest();
      reqBody.userId = userId;
      reqBody.loginToken = loginToken;
      reqBody.deviceName = 'HarmonyOS phone';
      await ApiClient.shared.post('/auth/mobile-login/request', reqBody, false);
      const confirmBody = new MobileLoginConfirmRequest();
      confirmBody.loginToken = loginToken;
      confirmBody.approved = true;
      await ApiClient.shared.post('/auth/mobile-login/confirm', confirmBody, false);

      const statusBody = new MobileLoginStatusRequest();
      statusBody.loginToken = loginToken;
      let status = 'pending_scan';
      for (let i = 0; i < 60; i++) {
        const res = await ApiClient.shared.post('/auth/mobile-login/status', statusBody, false);
        status = Json.strOr(res, 'status', 'expired');
        if (status === 'approved' || status === 'consumed') break;
        if (status === 'rejected' || status === 'expired') {
          throw new Error(`login ${status}`);
        }
        await new Promise<void>((resolve) => setTimeout(resolve, 2000));
      }
      if (status !== 'approved' && status !== 'consumed') {
        throw new Error('login not approved on web');
      }
      const exBody = new MobileLoginExchangeRequest();
      exBody.userId = userId;
      exBody.loginToken = loginToken;
      const ex = await ApiClient.shared.post('/auth/mobile-login/exchange', exBody, false);
      const user = AuthUser.fromJson(Json.obj(ex, 'auth'));
      const token = Json.strOr(Json.obj(ex, 'auth'), 'accessToken', '');
      await AppState.shared.signIn(server, token, user);
      this.qrOpen = false;
      this.toast('QR login complete');
    } catch (e) {
      const err = e as Error;
      const msg = err instanceof ApiError ? err.message : 'qr login failed';
      this.toast(msg);
    } finally {
      this.busy = false;
    }
  }

  build() {
    Column() {
      Column() {
        Text('Agents Anywhere')
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.text)
          .margin({ top: 64, bottom: 6 })
        Text('HarmonyOS control client')
          .fontSize(Theme.fontSmall)
          .fontColor(Theme.faint)
          .margin({ bottom: 28 })
      }

      Column({ space: 12 }) {
        Text('SERVER')
          .fontSize(Theme.fontTiny)
          .fontColor(Theme.faint)
          .alignSelf(ItemAlign.Start)
        Row({ space: 8 }) {
          TextInput({ placeholder: 'https://…', text: this.serverUrl })
            .height(44)
            .layoutWeight(1)
            .fontSize(Theme.fontSmall)
            .backgroundColor(Theme.bg)
            .fontColor(Theme.text)
            .caretColor(Theme.accent)
            .placeholderColor(Theme.faint)
            .borderRadius(10)
            .onChange((v: string) => {
              this.serverUrl = v;
              this.serverOk = false;
            })
          Button('Check')
            .height(44)
            .fontSize(Theme.fontSmall)
            .enabled(!this.busy)
            .backgroundColor(Theme.raised)
            .fontColor(Theme.text)
            .border({ width: 1, color: Theme.border })
            .borderRadius(10)
            .onClick(() => this.checkServer())
        }
        Text(this.serverHint)
          .fontSize(Theme.fontTiny)
          .fontColor(this.serverOk ? Theme.accent : Theme.warn)
          .alignSelf(ItemAlign.Start)
      }
      .padding(16)
      .backgroundColor(Theme.surface)
      .borderRadius(Theme.radiusCard)
      .margin({ left: 24, right: 24, top: 8 })

      Column({ space: 12 }) {
        Text('ACCOUNT')
          .fontSize(Theme.fontTiny)
          .fontColor(Theme.faint)
          .alignSelf(ItemAlign.Start)
        TextInput({ placeholder: 'Email', text: this.email })
          .height(44)
          .fontSize(Theme.fontSmall)
          .backgroundColor(Theme.bg)
          .fontColor(Theme.text)
          .caretColor(Theme.accent)
          .placeholderColor(Theme.faint)
          .borderRadius(10)
          .onChange((v: string) => {
            this.email = v;
          })
        TextInput({ placeholder: 'Password', text: this.password })
          .type(InputType.Password)
          .showPasswordIcon(true)
          .height(44)
          .fontSize(Theme.fontSmall)
          .backgroundColor(Theme.bg)
          .fontColor(Theme.text)
          .caretColor(Theme.accent)
          .placeholderColor(Theme.faint)
          .borderRadius(10)
          .onChange((v: string) => {
            this.password = v;
          })
        Button('Sign in')
          .height(44)
          .width('100%')
          .fontSize(Theme.fontBody)
          .fontWeight(FontWeight.Medium)
          .enabled(!this.busy)
          .backgroundColor(Theme.accent)
          .fontColor(Theme.onAccent)
          .borderRadius(10)
          .opacity(this.busy ? 0.5 : 1)
          .onClick(() => this.signIn())
        Button(this.qrOpen ? 'Hide QR login' : 'QR login (paste payload)')
          .height(40)
          .width('100%')
          .fontSize(Theme.fontTiny)
          .enabled(!this.busy)
          .backgroundColor(Theme.raised)
          .fontColor(Theme.muted)
          .border({ width: 1, color: Theme.border })
          .borderRadius(10)
          .onClick(() => {
            this.qrOpen = !this.qrOpen;
          })
        if (this.qrOpen) {
          TextArea({ placeholder: '{"serverUrl":…,"userId":"…","loginToken":"…"}', text: this.qrText })
            .height(110)
            .fontSize(Theme.fontTiny)
            .backgroundColor(Theme.bg)
            .fontColor(Theme.text)
            .caretColor(Theme.accent)
            .placeholderColor(Theme.faint)
            .borderRadius(10)
            .onChange((v: string) => {
              this.qrText = v;
            })
          Button('Scan payload login')
            .height(40)
            .width('100%')
            .fontSize(Theme.fontTiny)
            .enabled(!this.busy)
            .backgroundColor(Theme.raised)
            .fontColor(Theme.text)
            .borderRadius(10)
            .onClick(() => this.qrLogin())
        }
      }
      .padding(16)
      .backgroundColor(Theme.surface)
      .borderRadius(Theme.radiusCard)
      .margin({ left: 24, right: 24, top: 16 })

      if (this.busy) {
        LoadingProgress()
          .width(24)
          .height(24)
          .color(Theme.accent)
          .margin({ top: 16 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.bg)
  }
}
