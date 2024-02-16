import SwiftUI
import MapKit
import SWXMLHash

struct ContentView: View {
    
    @State private var line: String = ""
    
    var body: some View {
        NavigationView {
            VStack {
                Image("kmlodz-logo")
                    .resizable()
                    .frame(width: 200, height: 200)
                    .cornerRadius(10)
                    .padding(.bottom, 50)
                Text("Jakiej linii szukasz?")
                    .bold()
                    .font(.title)
                    .navigationTitle("MPK-Łódź - Lokalizacja pojazdów")
                    .navigationBarTitleDisplayMode(.inline)
                TextField("Numer linii", text: $line)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.all, 10)
                    .cornerRadius(10)
                    .frame(width: 200)
                    .multilineTextAlignment(.center)
                NavigationLink("Sprawdź lokalizację", destination: MapView(line: line))
                    .padding(.top, 15)
                    .bold()
                Spacer()
                Text("2024 kmLodz")
                    .multilineTextAlignment(.center)
            }
            .padding()
        }.accentColor(.black)
    }
}

struct MapView: View {
    
    let line: String
    @State private var vehicleInfos: [VehicleInfo] = []
    @State private var errorMessage: String? = nil
    @State private var timer: Timer?
    
    var body: some View {
        VStack {
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .padding()
                    .multilineTextAlignment(.center)
                    .bold()
            } else {
                Text("Linia: \(line.uppercased())")
                    .bold()
                Text("Aktualna liczba pojazdów: \(vehicleInfos.count)")
                    .padding(.bottom)
                    .font(.subheadline)
                MapViewRepresentable(vehicleInfos: vehicleInfos)
                    .frame(height: 600)
                    .cornerRadius(0)
                    .onAppear {
                        fetchVehicleCoordinates()
                        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in
                            fetchVehicleCoordinates()
                        }
                    }
                    .onDisappear {
                        timer?.invalidate()
                        timer = nil
                    }
                Text("Źródło danych: http://rozklady.lodz.pl")
                    .multilineTextAlignment(.center)
            }
        }
    }
    
    private func fetchVehicleCoordinates() {
        guard let url = URL(string: "http://rozklady.lodz.pl/Home/CNR_GetVehicles") else {
            print("Invalid URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let postData = "r=\(line.uppercased())".data(using: .utf8)
        request.httpBody = postData
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                print("Error: \(error?.localizedDescription ?? "Unknown error")")
                return
            }
            
            if let xmlString = String(data: data, encoding: .utf8) {
                if let vehicleInfos = parseXMLForVehicleInfos(xmlString) {
                    DispatchQueue.main.async {
                        self.errorMessage = nil
                        self.vehicleInfos = vehicleInfos
                    }
                } else {
                    DispatchQueue.main.async {
                        self.errorMessage = "Brak danych"
                        self.vehicleInfos = []
                    }
                }
            }
        }
        task.resume()
    }
    
    private func parseXMLForVehicleInfos(_ xmlString: String) -> [VehicleInfo]? {
        let xml = XMLHash.parse(xmlString)
        let vehicleElements = xml["VL"]["p"].all
        
        guard !vehicleElements.isEmpty else {
            print("Unable to find vehicle data in XML")
            return nil
        }
        
        var vehicleInfos: [VehicleInfo] = []
        
        for vehicleElement in vehicleElements {
            if let coordinateString = vehicleElement.element?.text {
                let vehicleComponents = coordinateString.components(separatedBy: ", ")
                
                if vehicleComponents.count >= 11,
                   let latitude = Double(vehicleComponents[10]),
                   let longitude = Double(vehicleComponents[9]) {
                    let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                    let vehicleNumber = vehicleComponents[1]
                    let vehicleInfo = VehicleInfo(coordinate: coordinate, vehicleNumber: vehicleNumber)
                    vehicleInfos.append(vehicleInfo)
                }
            }
        }
        
        return vehicleInfos
    }
}

struct MapViewRepresentable: UIViewRepresentable {
    
    var vehicleInfos: [VehicleInfo]
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        return mapView
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {
        mapView.removeAnnotations(mapView.annotations)
        
        guard !vehicleInfos.isEmpty else { return }
        
        var minLatitude = vehicleInfos.first!.coordinate.latitude
        var maxLatitude = vehicleInfos.first!.coordinate.latitude
        var minLongitude = vehicleInfos.first!.coordinate.longitude
        var maxLongitude = vehicleInfos.first!.coordinate.longitude
        
        for vehicleInfo in vehicleInfos {
            let annotation = MKPointAnnotation()
            annotation.coordinate = vehicleInfo.coordinate
            annotation.title = vehicleInfo.vehicleNumber
            mapView.addAnnotation(annotation)
            
            minLatitude = min(minLatitude, vehicleInfo.coordinate.latitude)
            maxLatitude = max(maxLatitude, vehicleInfo.coordinate.latitude)
            minLongitude = min(minLongitude, vehicleInfo.coordinate.longitude)
            maxLongitude = max(maxLongitude, vehicleInfo.coordinate.longitude)
        }
        
        let center: CLLocationCoordinate2D
        let span: MKCoordinateSpan
        
        if vehicleInfos.count == 1 {
            center = vehicleInfos.first!.coordinate
            span = MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
        } else {
            center = CLLocationCoordinate2D(latitude: (minLatitude + maxLatitude) / 2, longitude: (minLongitude + maxLongitude) / 2)
            span = MKCoordinateSpan(latitudeDelta: (maxLatitude - minLatitude) * 1.1, longitudeDelta: (maxLongitude - minLongitude) * 1.1)
        }
        
        let region = MKCoordinateRegion(center: center, span: span)
        mapView.setRegion(region, animated: true)
    }

    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapViewRepresentable
        
        init(_ parent: MapViewRepresentable) {
            self.parent = parent
        }
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard !(annotation is MKUserLocation) else {
                return nil
            }
            
            let annotationView = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "marker")
            annotationView.glyphImage = UIImage(systemName: "bus")
            annotationView.isEnabled = true
            annotationView.canShowCallout = true
            annotationView.markerTintColor = UIColor.systemBlue
            
            return annotationView
        }
        
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let annotation = view.annotation {
                let region = MKCoordinateRegion(center: annotation.coordinate, latitudinalMeters: 1000, longitudinalMeters: 1000)
                mapView.setRegion(region, animated: true)
            }
        }
    }
}

struct VehicleInfo {
    let coordinate: CLLocationCoordinate2D
    let vehicleNumber: String
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
