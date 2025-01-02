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
            
            VStack {
                Text("WARNING: Use at your own risk")
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("I am not responsible for any damage, data loss, or any other issues caused by using this tool.")
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .foregroundStyle(.red)
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
                            TextField("2FA Code", text: $code)
                                .textContentType(.oneTimeCode)
                                .keyboardType(.numberPad)
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.gray)
                                Text("You WILL need to give a 2FA code to successfully log in.")
                                    .font(.caption)
                                    .foregroundStyle(.gray)
                            }
                        }
                        
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
                    .cornerRadius(15)
                }
            }
            Spacer()
            FooterView()
        }
        .transition(.slide)
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
    }
}

#Preview {
    ContentView()
}
