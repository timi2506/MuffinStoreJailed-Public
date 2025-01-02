//
//  ContentView.swift
//  MuffinStoreJailed
//
//  Created by Mineek on 26/12/2024.
//

import SwiftUI

struct HeaderView: View {
    var body: some View {
        VStack {
            Text("MuffinStore Jailed")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("by @mineekdev")
                .font(.caption)
        }
    }
}

struct FooterView: View {
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title)
                .foregroundStyle(.red)

            
            VStack {
                Text("WARNING: Use at your own risk")
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("I am not responsible for any damage, data loss, or any other issues caused by using this tool.")
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.75))
                    .frame(maxWidth: .infinity, alignment: .leading)
                
            }
        }
    }
}

struct ContentView: View {
    @State var ipaTool: IPATool?
    
    @State var appleId: String = ""
    @State var password: String = ""
    @State var code: String = ""
    
    @State var isAuthenticated: Bool = false
    @State var isDowngrading: Bool = false
    @AppStorage("Downgrade Progress") var downgradeProgress = 0.1
    @State var DoneDisabled = true
    @State var tfa_Prompt = false
    @State var appStoreLinkPrompt = false
    
    @State var appLink: String = ""

    var body: some View {
        VStack {
            HeaderView()
            Spacer()
            if !isAuthenticated {
                List {
                    Section("Log in to the App Store") {
                        Text("Your credentials will be sent directly to Apple.")
                            .font(.caption)
                            .foregroundStyle(.gray)
                        TextField("Apple ID", text: $appleId)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                        VStack {
                            HStack {
                                TextField("2FA Code", text: $code)
                                    .textContentType(.oneTimeCode)
                                    .keyboardType(.numberPad)
                                Button(action: {
                                    if isNumeric(UIPasteboard.general.string ?? "") {
                                        code = UIPasteboard.general.string ?? ""
                                    }
                                    else {
                                        tfa_Prompt = true
                                    }
                                }) {
                                    Image(systemName: "document.on.clipboard")
                                        .font(.caption)
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                Text("You WILL need to give a 2FA code to successfully log in.")
                                    .font(.caption)
                            }
                            .foregroundStyle(.red.opacity(0.5))
                            .padding(2.5)
                        
                        Button("Authenticate") {
                            if appleId.isEmpty || password.isEmpty {
                                return
                            }
                            if code.isEmpty {
                                // we can just try to log in and it'll request a code, very scuffed tho.
                                ipaTool = IPATool(appleId: appleId, password: password)
                                ipaTool?.authenticate(requestCode: true)
                                return
                            }
                            let finalPassword = password + code
                            ipaTool = IPATool(appleId: appleId, password: finalPassword)
                            let ret = ipaTool?.authenticate()
                            isAuthenticated = ret ?? false
                        }
                        
                        
                    }
                }
                .scrollContentBackground(.hidden)
                .background(.gray.opacity(0.10))
                .cornerRadius(15)

               
            } else {
                if isDowngrading {
                    List {
                        Section("Please wait...") {
                                ProgressView(value: downgradeProgress)
                                    .progressViewStyle(LinearProgressViewStyle())
                                    .onChange(of: downgradeProgress) { newValue in
                                        if downgradeProgress == 1.0 {
                                            DoneDisabled = false
                                        }
                                    }
                            if downgradeProgress != 1.0 {
                                Text("Please wait while the app is being downgraded.")
                                    .font(.headline)

                                Text("This may take a while, only press the Done Button once the Install Popup appears")
                            }
                            
                            if downgradeProgress == 1.0 {
                                HStack {
                                    Image(systemName: "checkmark")
                                    Text("Finished downgrading, please press install in the popup displayed")
                                }
                                .foregroundStyle(.green)

                                Text("Then, press Done at the bottom of this page to close MuffinStore to be able to downgrade another app")
                                .foregroundStyle(.green)
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(.gray.opacity(0.10))
                    .cornerRadius(15)
                    
                    VStack {
                        Button("Done (exit app)") {
                            exit(0) // scuffed
                        }
                        .disabled(DoneDisabled)
                        .padding()
                    }
                } else {
                    List {
                        Section("Downgrade an app") {
                            VStack {
                                TextField("App Store Link", text: $appLink)
                                    .keyboardType(.URL)
                                    .textContentType(.URL)
                                Text("Enter the App Store link of the app you want to downgrade.")
                                    .font(.caption)
                                    .foregroundStyle(.gray)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Button("Paste App Store Link", systemImage: "document.on.clipboard") {
                                    if UIPasteboard.general.string!.contains("apps.apple.com") {
                                        // Contains apps.apple.com
                                    }
                                    else {
                                        appStoreLinkPrompt = true
                                    }
                                }
                            }
                            Button("Downgrade") {
                                if appLink.isEmpty {
                                    return
                                }
                                var appLinkParsed = appLink
                                appLinkParsed = appLinkParsed.components(separatedBy: "id").last ?? ""
                                for char in appLinkParsed {
                                    if !char.isNumber {
                                        appLinkParsed = String(appLinkParsed.prefix(upTo: appLinkParsed.firstIndex(of: char)!))
                                        break
                                    }
                                }
                                print("App ID: \(appLinkParsed)")
                                isDowngrading = true
                                downgradeProgress = 0.1
                                downgradeApp(appId: appLinkParsed, ipaTool: ipaTool!)
                            }
                        }
                        Section("Settings") {
                            VStack {
                                Button("Log out and exit") {
                                    isAuthenticated = false
                                    EncryptedKeychainWrapper.nuke()
                                    EncryptedKeychainWrapper.generateAndStoreKey()
                                    sleep(3)
                                    exit(0) // scuffed
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                Text("This will remove your Apple ID and it's credentials from the App and then Exit the App")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .font(.caption)
                                    .foregroundStyle(.gray)
                            }
                            

                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(.gray.opacity(0.10))
                    .cornerRadius(15)
                }
            }
            Spacer()
            FooterView()
        }
        .transition(.scale)
        .animation(.bouncy)
        .padding()
        .onAppear {
            downgradeProgress = 0.1
            isAuthenticated = EncryptedKeychainWrapper.hasAuthInfo()
            print("Found \(isAuthenticated ? "auth" : "no auth") info in keychain")
            if isAuthenticated {
                guard let authInfo = EncryptedKeychainWrapper.getAuthInfo() else {
                    print("Failed to get auth info from keychain, logging out")
                    isAuthenticated = false
                    EncryptedKeychainWrapper.nuke()
                    EncryptedKeychainWrapper.generateAndStoreKey()
                    return
                }
                appleId = authInfo["appleId"]! as! String
                password = authInfo["password"]! as! String
                ipaTool = IPATool(appleId: appleId, password: password)
                let ret = ipaTool?.authenticate()
                print("Re-authenticated \(ret! ? "successfully" : "unsuccessfully")")
            } else {
                print("No auth info found in keychain, setting up by generating a key in SEP")
                EncryptedKeychainWrapper.generateAndStoreKey()
            }
        }
        .alert(isPresented: $tfa_Prompt) {
            Alert(title: Text("Are you sure this is a 2FA Code?"), message: Text("Your clipboard contents don't look like a 2FA code, are you sure you pasted the right thing? \n \n \(UIPasteboard.general.string ?? "ClipboardEmpty")"), primaryButton: .default(Text("Paste anyways"), action: {
                code = UIPasteboard.general.string ?? ""
            }), secondaryButton: .default(Text("Cancel")))
        }
        .alert(isPresented: $appStoreLinkPrompt) {
            Alert(title: Text("Are you sure this is an App Store Link?"), message: Text("Your clipboard contents don't look like an App Store Link, are you sure you pasted the right thing? \n \n \(UIPasteboard.general.string ?? "ClipboardEmpty")"), primaryButton: .default(Text("Paste anyways"), action: {
                appLink = UIPasteboard.general.string ?? ""
            }), secondaryButton: .default(Text("Cancel")))
        }
    }
    func isNumeric(_ code: String) -> Bool {
        let numberSet = CharacterSet.decimalDigits
        return code.unicodeScalars.allSatisfy { numberSet.contains($0) }
    }
}

#Preview {
    ContentView()
}
